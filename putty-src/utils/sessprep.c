/*
 * sessprep.c: centralise some preprocessing done on Conf objects
 * before launching them.
 */

#include "putty.h"

void prepare_session(Conf *conf)
{
    char *hostbuf = dupstr(conf_get_str(conf, CONF_host));
    char *host = hostbuf;
    char *p, *q;

    /*
     * Trim leading whitespace from the hostname. In particular, pasted
     * host names can contain CR/LF characters that a single-line edit box
     * does not visibly distinguish from an otherwise valid address.
     */
    while (*host && isspace((unsigned char)*host))
        host++;

    /*
     * See if host is of the form user@host, and separate out the
     * username if so.
     */
    if (host[0] != '\0') {
        /*
         * Use strrchr, in case the _username_ in turn is of the form
         * user@host, which has been known.
         */
        char *atsign = strrchr(host, '@');
        if (atsign) {
            *atsign = '\0';
            conf_set_str(conf, CONF_username, host);
            host = atsign + 1;
        }
    }

    /*
     * Trim a colon suffix off the hostname if it's there, and discard
     * the text after it.
     *
     * The exact reason why we _ignore_ this text, rather than
     * treating it as a port number, is unfortunately lost in the
     * mists of history: the commit which originally introduced this
     * change on 2001-05-06 was clear on _what_ it was doing but
     * didn't bother to explain _why_. But I [SGT, 2017-12-03] suspect
     * it has to do with priority order: what should a saved session
     * do if its CONF_host contains 'server.example.com:123' and its
     * CONF_port contains 456? If CONF_port contained the _default_
     * port number then it might be a good guess that the colon suffix
     * on the host name was intended to override that, but you don't
     * really want to get into making heuristic judgments on that
     * basis.
     *
     * (Then again, you could just as easily make the same argument
     * about whether a 'user@' prefix on the host name should override
     * CONF_username, which this code _does_ do. I don't have a good
     * answer, sadly. Both these pieces of behaviour have been around
     * for years and it would probably cause subtle breakage in all
     * sorts of long-forgotten scripting to go changing things around
     * now.)
     *
     * In order to protect unbracketed IPv6 address literals against
     * this treatment, we do not make this change at all if there's
     * _more_ than one (un-IPv6-bracketed) colon.
     */
    p = host_strchr(host, ':');
    if (p && p == host_strrchr(host, ':')) {
        *p = '\0';
    }

    /*
     * Remove any remaining ASCII whitespace. Previously this only removed
     * spaces and tabs, so a pasted address ending in CR/LF was displayed as
     * a valid host but failed in getaddrinfo with WSAHOST_NOT_FOUND.
     */
    p = hostbuf;
    q = host;
    while (*q) {
        if (!isspace((unsigned char)*q))
            *p++ = *q;
        q++;
    }
    *p = '\0';

    conf_set_str(conf, CONF_host, hostbuf);
    sfree(hostbuf);

    /* Keep interactive network sessions alive across idle relay timeouts.
     * A non-zero SSH/Telnet keepalive is harmless for active sessions, while
     * TCP keepalive also covers Raw connections used by bastion clients. */
    if (conf_get_int(conf, CONF_protocol) != PROT_SERIAL) {
        if (conf_get_int(conf, CONF_ping_interval) <= 0 ||
            conf_get_int(conf, CONF_ping_interval) > 30)
            conf_set_int(conf, CONF_ping_interval, 30);
        conf_set_bool(conf, CONF_tcp_keepalives, true);
    }
}
