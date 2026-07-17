/*
 * Native Windows AI side panel for PuTTY AI.
 */

#ifndef PUTTY_WINDOWS_AI_H
#define PUTTY_WINDOWS_AI_H

#include <windows.h>

typedef struct WinGuiSeat WinGuiSeat;
typedef struct AiPanel AiPanel;

#define WM_PUTTY_AI_RESPONSE (WM_APP + 40)

int ai_panel_default_width(void);
AiPanel *ai_panel_create(WinGuiSeat *wgs);
void ai_panel_destroy(AiPanel *panel);
int ai_panel_width(const AiPanel *panel);
void ai_panel_layout(AiPanel *panel);
bool ai_panel_handle_command(
    AiPanel *panel, unsigned id, unsigned notification, HWND control);
bool ai_panel_handle_message(
    AiPanel *panel, UINT message, WPARAM wParam, LPARAM lParam,
    LRESULT *result);

#endif
