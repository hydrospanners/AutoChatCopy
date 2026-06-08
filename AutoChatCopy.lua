local ADDON_NAME = ...
local MAX_LINES_PER_FRAME = 4096
local CHAT_FRAME_MAX_LINES = 4096
local MAX_TRANSCRIPT_LETTERS = 200000
local BUTTON_ALPHA_IDLE = 0.22
local BUTTON_ALPHA_HOVER = 0.9

local frameLogs = {}
local copyDialog

local function GetFrameKey(chatFrame)
    return chatFrame and chatFrame:GetName() or nil
end

local function EnsureFrameLog(chatFrame)
    local key = GetFrameKey(chatFrame)
    if not key then
        return nil
    end

    local log = frameLogs[key]
    if not log then
        log = {}
        frameLogs[key] = log
    end
    return log
end

local function SanitizeChatLine(text)
    if type(text) ~= "string" then
        return ""
    end

    -- Some chat payloads are protected/secret strings in modern Retail.
    -- Any string ops on those can throw, so sanitize through pcall.
    local ok, sanitized = pcall(function()
        local value = text
        value = value:gsub("|c%x%x%x%x%x%x%x%x", "")
        value = value:gsub("|r", "")
        value = value:gsub("|T.-|t", "")
        value = value:gsub("|H.-|h(.-)|h", "%1")
        return value
    end)

    if ok and type(sanitized) == "string" then
        return sanitized
    end

    return "[Protected chat line]"
end

local function TrackChatLine(chatFrame, text)
    local log = EnsureFrameLog(chatFrame)
    if not log then
        return
    end

    local safeText = SanitizeChatLine(text)
    if safeText == "" then
        return
    end

    log[#log + 1] = safeText
    if #log > MAX_LINES_PER_FRAME then
        table.remove(log, 1)
    end
end

local function SetChatFrameHistoryLimit(chatFrame)
    if not chatFrame then
        return
    end

    pcall(function()
        if chatFrame:GetMaxLines() < CHAT_FRAME_MAX_LINES then
            chatFrame:SetMaxLines(CHAT_FRAME_MAX_LINES)
        end
    end)
end

local function ReadChatFrameHistory(chatFrame)
    if not chatFrame then
        return nil
    end

    local ok, numMessages = pcall(chatFrame.GetNumMessages, chatFrame)
    if not ok or type(numMessages) ~= "number" or numMessages <= 0 then
        return nil
    end

    local lines = {}
    local startMessage = math.max(1, numMessages - MAX_LINES_PER_FRAME + 1)
    for messageIndex = startMessage, numMessages do
        local messageOk, message = pcall(chatFrame.GetMessageInfo, chatFrame, messageIndex)
        if messageOk then
            local safeText = SanitizeChatLine(message)
            if safeText ~= "" then
                lines[#lines + 1] = safeText
            end
        end
    end

    return lines
end

local function SeedFrameLogFromHistory(chatFrame)
    local history = ReadChatFrameHistory(chatFrame)
    if not history or #history == 0 then
        return
    end

    local log = EnsureFrameLog(chatFrame)
    if not log then
        return
    end

    wipe(log)
    for index = 1, #history do
        log[index] = history[index]
    end
end

local function BuildFrameTranscript(chatFrame)
    local history = ReadChatFrameHistory(chatFrame)
    if history and #history > 0 then
        return table.concat(history, "\n")
    end

    local log = EnsureFrameLog(chatFrame)
    if not log or #log == 0 then
        return "No captured chat history yet for this chat window."
    end
    return table.concat(log, "\n")
end

local function EnsureCopyDialog()
    if copyDialog then
        return copyDialog
    end

    local dialog = CreateFrame("Frame", "AutoChatCopyDialog", UIParent, "BasicFrameTemplateWithInset")
    dialog:SetSize(780, 520)
    dialog:SetPoint("CENTER")
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:Hide()
    table.insert(UISpecialFrames, dialog:GetName())

    dialog.TitleText:SetText("AutoChatCopy")

    local dragHandle = CreateFrame("Frame", nil, dialog)
    dragHandle:SetPoint("TOPLEFT", dialog, "TOPLEFT", 0, 0)
    dragHandle:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", 0, 0)
    dragHandle:SetHeight(28)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        dialog:StartMoving()
    end)
    dragHandle:SetScript("OnDragStop", function()
        dialog:StopMovingOrSizing()
    end)

    local subtitle = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -34)
    subtitle:SetText("Drag to select part of the transcript, then press Ctrl-C to copy and close.")

    local scrollingEditBox = CreateFrame("Frame", nil, dialog, "ScrollingEditBoxTemplate")
    scrollingEditBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -58)
    scrollingEditBox:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -36, 18)

    local scrollBar = CreateFrame("EventFrame", nil, dialog, "MinimalScrollBar")
    scrollBar:SetPoint("TOPRIGHT", scrollingEditBox, "TOPRIGHT", -5, 0)
    scrollBar:SetPoint("BOTTOMRIGHT", scrollingEditBox, "BOTTOMRIGHT", -5, -1)

    local scrollBox = scrollingEditBox:GetScrollBox()
    ScrollUtil.RegisterScrollBoxWithScrollBar(scrollBox, scrollBar)
    if scrollBox:GetView() and scrollBox:GetView().SetPanExtent then
        scrollBox:GetView():SetPanExtent(50)
    end
    ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar, {
        CreateAnchor("TOPLEFT", scrollingEditBox, "TOPLEFT", 0, 0),
        CreateAnchor("BOTTOMRIGHT", scrollingEditBox, "BOTTOMRIGHT", -18, -1),
    }, {
        CreateAnchor("TOPLEFT", scrollingEditBox, "TOPLEFT", 0, 0),
        CreateAnchor("BOTTOMRIGHT", scrollingEditBox, "BOTTOMRIGHT", -2, -1),
    })

    local copyCloseQueued = false
    local function CloseDialogAfterCopy()
        if copyCloseQueued then
            return
        end

        copyCloseQueued = true
        C_Timer.After(0.1, function()
            copyCloseQueued = false
            if dialog:IsShown() then
                dialog:Hide()
            end
        end)
    end

    local editBox = scrollingEditBox:GetEditBox()
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(MAX_TRANSCRIPT_LETTERS)
    editBox:EnableMouse(true)

    scrollingEditBox:RegisterCallback("OnEscapePressed", function()
        editBox:ClearFocus()
    end)

    editBox:HookScript("OnKeyUp", function(_, key)
        if key == "C" and IsControlKeyDown() then
            CloseDialogAfterCopy()
        end
    end)
    editBox:HookScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then
            return
        end

        local cursorPosition = self:GetCursorPosition() or 0
        if IsShiftKeyDown() and self.autoChatCopySelectionAnchor then
            local startPosition = math.min(self.autoChatCopySelectionAnchor, cursorPosition)
            local endPosition = math.max(self.autoChatCopySelectionAnchor, cursorPosition)
            self:HighlightText(startPosition, endPosition)
        else
            self.autoChatCopySelectionAnchor = cursorPosition
        end
    end)

    dialog.scrollingEditBox = scrollingEditBox
    dialog.editBox = editBox
    copyDialog = dialog

    return dialog
end

local function OpenCopyDialog(chatFrame)
    local dialog = EnsureCopyDialog()
    local transcript = BuildFrameTranscript(chatFrame)
    dialog.scrollingEditBox:SetText(transcript)
    dialog:Show()
    dialog:Raise()

    C_Timer.After(0, function()
        if dialog:IsShown() then
            dialog.editBox:SetFocus()
            dialog.editBox:SetCursorPosition(0)
            dialog.editBox:HighlightText(0, 0)
            dialog.editBox.autoChatCopySelectionAnchor = 0
        end
    end)
end

local function HookChatFrame(chatFrame)
    if not chatFrame or chatFrame.autoChatCopyHooked then
        return
    end

    SetChatFrameHistoryLimit(chatFrame)
    SeedFrameLogFromHistory(chatFrame)

    hooksecurefunc(chatFrame, "AddMessage", function(self, text)
        -- Login/system events from other addons can emit protected strings.
        -- Never allow our passive capture hook to throw into chat processing.
        local ok = pcall(TrackChatLine, self, text)
        if not ok then
            return
        end
    end)

    local button = CreateFrame("Button", nil, chatFrame)
    button:SetSize(16, 16)
    button:SetPoint("TOPRIGHT", chatFrame, "TOPRIGHT", -3, -3)
    button:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    button:SetHighlightTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Down")
    button:SetPushedTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    button:SetAlpha(BUTTON_ALPHA_IDLE)

    button:SetScript("OnEnter", function(self)
        self:SetAlpha(BUTTON_ALPHA_HOVER)
    end)
    button:SetScript("OnLeave", function(self)
        self:SetAlpha(BUTTON_ALPHA_IDLE)
    end)
    button:SetScript("OnClick", function()
        OpenCopyDialog(chatFrame)
    end)

    button:SetScript("OnShow", function(self)
        self:SetAlpha(BUTTON_ALPHA_IDLE)
    end)

    chatFrame.autoChatCopyButton = button
    chatFrame.autoChatCopyHooked = true
end

local function HookAllChatFrames()
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame then
            HookChatFrame(chatFrame)
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        HookAllChatFrames()
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            HookAllChatFrames()
        end)
    end
end)

SLASH_AUTOCHATCOPY1 = "/autochatcopy"
SLASH_AUTOCHATCOPY2 = "/accopy"
SlashCmdList.AUTOCHATCOPY = function()
    local frame = SELECTED_DOCK_FRAME or DEFAULT_CHAT_FRAME
    if not frame then
        print("|cffffff00AutoChatCopy:|r no active chat frame available.")
        return
    end
    OpenCopyDialog(frame)
end
