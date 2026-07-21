#include "putty.h"
#include "storage.h"

#include <tlhelp32.h>

extern bool sesslist_demo_mode;
extern Filename *dialog_box_demo_screenshot_filename;
static strbuf *demo_terminal_data = NULL;
static Filename *terminal_demo_screenshot_filename;

const unsigned cmdline_tooltype =
    TOOLTYPE_HOST_ARG |
    TOOLTYPE_PORT_ARG |
    TOOLTYPE_NO_VERBOSE_OPTION;

static void launch_log_json_string(strbuf *out, const char *text)
{
    const unsigned char *p = (const unsigned char *)text;

    put_byte(out, '"');
    while (*p) {
        switch (*p) {
          case '"': put_fmt(out, "\\\""); break;
          case '\\': put_fmt(out, "\\\\"); break;
          case '\b': put_fmt(out, "\\b"); break;
          case '\f': put_fmt(out, "\\f"); break;
          case '\n': put_fmt(out, "\\n"); break;
          case '\r': put_fmt(out, "\\r"); break;
          case '\t': put_fmt(out, "\\t"); break;
          default:
            if (*p < 0x20)
                put_fmt(out, "\\u%04x", (unsigned)*p);
            else
                put_byte(out, *p);
            break;
        }
        p++;
    }
    put_byte(out, '"');
}

static DWORD launch_log_parent_process_id(void)
{
    DWORD current_pid = GetCurrentProcessId(), parent_pid = 0;
    PROCESSENTRY32W entry;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);

    if (snapshot == INVALID_HANDLE_VALUE)
        return 0;

    memset(&entry, 0, sizeof(entry));
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snapshot, &entry)) {
        do {
            if (entry.th32ProcessID == current_pid) {
                parent_pid = entry.th32ParentProcessID;
                break;
            }
        } while (Process32NextW(snapshot, &entry));
    }

    CloseHandle(snapshot);
    return parent_pid;
}

/*
 * Temporary AccessClient diagnostics. This intentionally records the exact
 * unredacted Windows command line before cmdline processing can wipe secrets
 * such as -pw. The resulting file must be protected and removed after the
 * integration problem has been diagnosed.
 */
static void write_accessclient_launch_log(const char *winmain_cmdline)
{
    wchar_t base[MAX_PATH], dir[MAX_PATH], path[MAX_PATH];
    wchar_t executable[MAX_PATH], cwd[MAX_PATH], parent_executable[MAX_PATH];
    wchar_t *winmain_wide;
    char *full_utf8, *winmain_utf8, *executable_utf8, *cwd_utf8;
    char *parent_executable_utf8;
    SYSTEMTIME now;
    HANDLE file, parent_process;
    DWORD written, length, parent_pid;
    strbuf *entry;

    length = GetEnvironmentVariableW(L"LOCALAPPDATA", base, lenof(base));
    if (!length || length >= lenof(base))
        return;

    _snwprintf(dir, lenof(dir), L"%s\\PuTTY AI", base);
    dir[lenof(dir) - 1] = L'\0';
    CreateDirectoryW(dir, NULL);
    _snwprintf(path, lenof(path), L"%s\\accessclient-launch.log", dir);
    path[lenof(path) - 1] = L'\0';

    executable[0] = L'\0';
    length = GetModuleFileNameW(NULL, executable, lenof(executable));
    if (!length || length >= lenof(executable))
        lstrcpynW(executable, L"[unavailable]", lenof(executable));

    cwd[0] = L'\0';
    length = GetCurrentDirectoryW(lenof(cwd), cwd);
    if (!length || length >= lenof(cwd))
        lstrcpynW(cwd, L"[unavailable]", lenof(cwd));

    parent_pid = launch_log_parent_process_id();
    lstrcpynW(parent_executable, L"[unavailable]", lenof(parent_executable));
    parent_process = OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION, FALSE, parent_pid);
    if (parent_process) {
        length = lenof(parent_executable);
        if (!QueryFullProcessImageNameW(
                parent_process, 0, parent_executable, &length))
            lstrcpynW(
                parent_executable, L"[unavailable]", lenof(parent_executable));
        CloseHandle(parent_process);
    }

    full_utf8 = dup_wc_to_mb(CP_UTF8, GetCommandLineW(), "");
    winmain_wide = dup_mb_to_wc(CP_ACP, winmain_cmdline ? winmain_cmdline : "");
    winmain_utf8 = dup_wc_to_mb(CP_UTF8, winmain_wide, "");
    executable_utf8 = dup_wc_to_mb(CP_UTF8, executable, "");
    cwd_utf8 = dup_wc_to_mb(CP_UTF8, cwd, "");
    parent_executable_utf8 = dup_wc_to_mb(CP_UTF8, parent_executable, "");
    sfree(winmain_wide);

    GetSystemTime(&now);
    entry = strbuf_new();
    put_fmt(
        entry,
        "{\"timestamp\":\"%04u-%02u-%02uT%02u:%02u:%02u.%03uZ\","
        "\"pid\":%lu,\"executable\":",
        now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
        now.wMilliseconds, (unsigned long)GetCurrentProcessId());
    launch_log_json_string(entry, executable_utf8);
    put_fmt(entry, ",\"parent_pid\":%lu,\"parent_executable\":",
            (unsigned long)parent_pid);
    launch_log_json_string(entry, parent_executable_utf8);
    put_fmt(entry, ",\"working_directory\":");
    launch_log_json_string(entry, cwd_utf8);
    put_fmt(entry, ",\"command_line\":");
    launch_log_json_string(entry, full_utf8);
    put_fmt(entry, ",\"winmain_arguments\":");
    launch_log_json_string(entry, winmain_utf8);
    put_fmt(entry, "}\r\n");

    file = CreateFileW(
        path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
        OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file != INVALID_HANDLE_VALUE) {
        WriteFile(file, entry->s, (DWORD)entry->len, &written, NULL);
        CloseHandle(file);
    }

    strbuf_free(entry);
    sfree(full_utf8);
    sfree(winmain_utf8);
    sfree(executable_utf8);
    sfree(cwd_utf8);
    sfree(parent_executable_utf8);
}

/*
 * AccessClient launches PuTTY with a saved Raw session whose port points at
 * its local relay, but some versions omit HostName. The normal PuTTY
 * behaviour is to open Configuration in that case. A direct automated
 * launch has no useful configuration interaction, so complete that form
 * with the loopback address instead.
 */
static bool complete_local_relay_destination(Conf *conf)
{
    if (conf_get_int(conf, CONF_protocol) != PROT_RAW ||
        conf_get_str(conf, CONF_host)[0] ||
        conf_get_int(conf, CONF_port) <= 0 ||
        conf_get_int(conf, CONF_port) > 65535)
        return false;

    conf_set_str(conf, CONF_host, "127.0.0.1");
    return true;
}

void gui_term_process_cmdline(Conf *conf, char *cmdline)
{
    char *p;
    bool special_launchable_argument = false;
    bool demo_config_box = false;

    write_accessclient_launch_log(cmdline);

    settings_set_default_protocol(be_default_protocol);
    /* Find the appropriate default port. */
    {
        const struct BackendVtable *vt =
            backend_vt_from_proto(be_default_protocol);
        settings_set_default_port(0); /* illegal */
        if (vt)
            settings_set_default_port(vt->default_port);
    }
    conf_set_int(conf, CONF_logtype, LGTYP_NONE);

    do_defaults(NULL, conf);

    p = handle_restrict_acl_cmdline_prefix(cmdline);

    if (handle_special_sessionname_cmdline(p, conf)) {
        /* Saved-session links (including Windows jump-list and bastion
         * launches) are explicit connection requests. Never divert them
         * into the Configuration dialog. */
        if (!conf_launchable(conf) && !complete_local_relay_destination(conf))
            cmdline_error(
                "the saved session selected for direct launch does not "
                "specify a destination");
        special_launchable_argument = true;
    } else if (handle_special_filemapping_cmdline(p, conf)) {
        if (!conf_launchable(conf) && !complete_local_relay_destination(conf))
            cmdline_error(
                "the file-mapped session selected for direct launch does not "
                "specify a destination");
        special_launchable_argument = true;
    } else if (!*p) {
        /* Do-nothing case for an empty command line - or rather,
         * for a command line that's empty _after_ we strip off
         * the &R prefix. */
    } else {
        /*
         * Otherwise, break up the command line and deal with
         * it sensibly.
         */
        CmdlineArgList *arglist = cmdline_arg_list_from_GetCommandLineW();
        size_t arglistpos = 0;
        while (arglist->args[arglistpos]) {
            CmdlineArg *arg = arglist->args[arglistpos++];
            CmdlineArg *nextarg = arglist->args[arglistpos];
            const char *p = cmdline_arg_to_str(arg);
            int ret = cmdline_process_param(arg, nextarg, 1, conf);
            if (ret == -2) {
                cmdline_error("option \"%s\" requires an argument", p);
            } else if (ret == 2) {
                arglistpos++;          /* skip next argument */
            } else if (ret == 1) {
                continue;          /* nothing further needs doing */
            } else if (!strcmp(p, "-cleanup")) {
                /*
                 * `putty -cleanup'. Remove all registry
                 * entries associated with PuTTY, and also find
                 * and delete the random seed file.
                 */
                char *s1, *s2;
                s1 = dupprintf("This procedure will remove ALL Registry entries\n"
                               "associated with %s, and will also remove\n"
                               "the random seed file. (This only affects the\n"
                               "currently logged-in user.)\n"
                               "\n"
                               "THIS PROCESS WILL DESTROY YOUR SAVED SESSIONS.\n"
                               "Are you really sure you want to continue?",
                               appname);
                s2 = dupprintf("%s Warning", appname);
                if (message_box(NULL, s1, s2,
                                MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2,
                                false, HELPCTXID(option_cleanup)) == IDYES) {
                    cleanup_all();
                }
                sfree(s1);
                sfree(s2);
                exit(0);
            } else if (!strcmp(p, "-pgpfp")) {
                pgp_fingerprints_msgbox(NULL);
                exit(0);
            } else if (has_ca_config_box &&
                       (!strcmp(p, "-host-ca") || !strcmp(p, "--host-ca") ||
                        !strcmp(p, "-host_ca") || !strcmp(p, "--host_ca"))) {
                show_ca_config_box(NULL);
                exit(0);
            } else if (!strcmp(p, "-demo-config-box")) {
                if (!arglist->args[arglistpos]) {
                    cmdline_error("%s expects an output filename", p);
                } else {
                    demo_config_box = true;
                    dialog_box_demo_screenshot_filename =
                        cmdline_arg_to_filename(arglist->args[arglistpos++]);
                }
            } else if (!strcmp(p, "-demo-terminal")) {
                if (!arglist->args[arglistpos] ||
                    !arglist->args[arglistpos+1]) {
                    cmdline_error("%s expects input and output filenames", p);
                } else {
                    const char *infile =
                        cmdline_arg_to_str(arglist->args[arglistpos++]);
                    terminal_demo_screenshot_filename =
                        cmdline_arg_to_filename(arglist->args[arglistpos++]);
                    FILE *fp = fopen(infile, "rb");
                    if (!fp)
                        cmdline_error("can't open input file '%s'", infile);
                    demo_terminal_data = strbuf_new();
                    char buf[4096];
                    int retd;
                    while ((retd = fread(buf, 1, sizeof(buf), fp)) > 0)
                        put_data(demo_terminal_data, buf, retd);
                    fclose(fp);
                }
            } else if (*p != '-') {
                cmdline_error("unexpected argument \"%s\"", p);
            } else {
                cmdline_error("unknown option \"%s\"", p);
            }
        }
    }

    cmdline_run_saved(conf);

    /*
     * AccessClient versions use both -load and an explicit -raw -P form.
     * In either form, the local relay port is the destination even when the
     * host argument is omitted. Keep ordinary `putty' launches interactive.
     */
    if (!conf_launchable(conf) &&
        (cmdline_loaded_session() || cmdline_port_argument()) &&
        complete_local_relay_destination(conf))
        special_launchable_argument = true;

    if (demo_config_box) {
        sesslist_demo_mode = true;
        load_open_settings(NULL, conf);
        conf_set_str(conf, CONF_host, "demo-server.example.com");
        do_config(conf);
        cleanup_exit(0);
    } else if (demo_terminal_data) {
        /* Ensure conf will cause an immediate session launch */
        load_open_settings(NULL, conf);
        conf_set_str(conf, CONF_host, "demo-server.example.com");
        conf_set_int(conf, CONF_close_on_exit, FORCE_OFF);
    } else {
        /*
         * Bring up the config dialog if the command line hasn't
         * (explicitly) specified a launchable configuration.
         */
        if (!(special_launchable_argument || cmdline_host_ok(conf))) {
            if (!do_config(conf))
                cleanup_exit(0);
        }
    }

    prepare_session(conf);
}

const struct BackendVtable *backend_vt_from_conf(Conf *conf)
{
    if (demo_terminal_data) {
        return &null_backend;
    }

    /*
     * Select protocol. This is farmed out into a table in a
     * separate file to enable an ssh-free variant.
     */
    const struct BackendVtable *vt = backend_vt_from_proto(
        conf_get_int(conf, CONF_protocol));
    if (!vt) {
        char *str = dupprintf("%s Internal Error", appname);
        MessageBox(NULL, "Unsupported protocol number found",
                   str, MB_OK | MB_ICONEXCLAMATION);
        sfree(str);
        cleanup_exit(1);
    }
    return vt;
}

const wchar_t *get_app_user_model_id(void)
{
    return L"SimonTatham.PuTTY";
}

static void demo_terminal_screenshot(void *ctx, unsigned long now)
{
    HWND hwnd = (HWND)ctx;
    char *err = save_screenshot(hwnd, terminal_demo_screenshot_filename);
    if (err) {
        MessageBox(hwnd, err, "Demo screenshot failure", MB_OK | MB_ICONERROR);
        sfree(err);
    }
    cleanup_exit(0);
}

void gui_terminal_ready(HWND hwnd, Seat *seat, Backend *backend)
{
    if (demo_terminal_data) {
        ptrlen data = ptrlen_from_strbuf(demo_terminal_data);
        seat_stdout(seat, data.ptr, data.len);
        schedule_timer(TICKSPERSEC, demo_terminal_screenshot, (void *)hwnd);
    }
}
