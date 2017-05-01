-- **************************************************************************
-- * Titan Currency .lua - VERSION 5.4b
-- **************************************************************************
-- * by Greenhorns @ Vek'Nilash
-- * This mod will display all the Currency you have on the curent toon
-- * in a tool tip.  It shows the curent Toons Gold amount on the Titan Panel
-- * bar.
-- *
-- **************************************************************************

-- ******************************** Constants *******************************
local TITAN_CURRENCY_ID = "Currency";
local TITAN_CURRENCY_COUNT_FORMAT = "%d";
local TITAN_CURRENCY_VERSION = "5.4b";
local TITAN_CURRENCY_SPACERBAR = "--------------------";
local TITAN_CURRENCY_BLUE  = {r=0.4, b=1.0, g=0.4};
local TITAN_CURRENCY_RED   = {r=1.0, b=0.0, g=0.0};
local TITAN_CURRENCY_GREEN = {r=0.0, b=0.0, g=1.0};
local CURRENCY_ICON_GOLD1 = "Interface\\MoneyFrame\\UI-MoneyIcons"; -- system icon of 3 coins (needs cropping)
local CURRENCY_ICON_GOLD2 = "Interface\\AddOns\\TitanGold\\Artwork\\TitanGold"; -- depends on Titan Gold
local CURRENCY_ICON_GOLD3 = "Interface\\Icons\\INV_Misc_Coin_01"; -- not found
-- ******************************** System Variables *******************************
local L = LibStub("AceLocale-3.0"):GetLocale("Titan", true)
local LB = LibStub("AceLocale-3.0"):GetLocale("Titan_Currency", true)
local TitanCurrency = LibStub("AceAddon-3.0"):NewAddon("TitanCurrency", "AceHook-3.0", "AceTimer-3.0")
local CurrencyTimer = nil;
local _G = getfenv(0);
-- ******************************** Variables *******************************
local CURRENCY_INITIALIZED = false;
local CURRENCY_VARIABLES_LOADED = false;
local CURRENCY_ENTERINGWORLD = false;
local CURRENCY_MENU_PREPARED = false;
--local CURRENCY_SELECTED_NAME = "Order Resources";
--local CURRENCY_SELECTED_NAME = "Gold";
local CURRENCY_SELECTED_NAME = "Legionfall War Supplies";
local CURRENCY_DATA = {};
local CURRENCY_IGNORE = {};

-- ignore list
CURRENCY_IGNORE["Garrison Resources"] = true;
CURRENCY_IGNORE["Apexis Crystal"] = true;
CURRENCY_IGNORE["Timeless Coin"] = true;
CURRENCY_IGNORE["Lesser Charm of Good Fortune"] = true;
CURRENCY_IGNORE["Elder Charm of Good Fortune"] = true;
CURRENCY_IGNORE["Ironpaw Token"] = true;
CURRENCY_IGNORE["Warforged Seal"] = true;

-- display order
-- TODO: this will miss new currencies!  make this dynamic w/ menu adjustments
local CURRENCY_ORDER = {
	"Gold",
	"Order Resources",
	"Legionfall War Supplies",
	"Ancient Mana",
	"Nethershard",
	"Sightless Eye",
	"Curious Coin",
};

-- ******************************** Functions *******************************

local function comma(amount)
	local formatted = ""..amount
	local k
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if (k==0) then break end
	end
	return formatted
end

function pp(s)
	DEFAULT_CHAT_FRAME:AddMessage(s, 0.3, 0.9, 0.8)
end


-- **************************************************************************
-- NAME : TitanPanelCurrencyButton_OnLoad()
-- DESC : Initialization (register with TitanPanel, register WOW events)
-- **************************************************************************
function TitanPanelCurrencyButton_OnLoad(self)
    -- register with TitanPanel
	self.registry = { 
		id = TITAN_CURRENCY_ID,
		-- builtIn = nil,
		category = "Information",
		version = TITAN_CURRENCY_VERSION,
		menuText = LB["TITAN_CURRENCY_MENU_TEXT"], 
		tooltipTitle = LB["TITAN_CURRENCY_TOOLTIP"],
		tooltipTextFunction = "TitanPanelCurrencyButton_GetTooltipText",
		buttonTextFunction = "TitanPanelCurrencyButton_GetButtonText",
		controlVariables = {
			DisplayOnRightSide = true,
		},
		savedVariables = {
			DisplayOnRightSide = false,             
		},
    };

	-- register with WOW
    self:RegisterEvent("VARIABLES_LOADED");
    self:RegisterEvent("PLAYER_ENTERING_WORLD");
    self:RegisterEvent("PLAYER_MONEY");
    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE");

	-- init display
	--TitanPanelCurrencyButton_UpdateButtonText();    
end

-- **************************************************************************
-- NAME : TitanPanelCurrencyButton_OnEvent()
-- DESC : Event handler
-- CALL : Called by WOW
-- **************************************************************************
function TitanCurrency_OnEvent(self, event, ...)
	pp(">>> Currency event - "..event);

	if (event == "VARIABLES_LOADED") then
		CURRENCY_VARIABLES_LOADED = true;
        if (CURRENCY_ENTERINGWORLD) then
			TitanPanelCurrencyButton_InitOnLoadedAndEntering(self);
        end
        return;
    end

    if ( event == "PLAYER_ENTERING_WORLD" ) then
        CURRENCY_ENTERINGWORLD = true;
        if (CURRENCY_VARIABLES_LOADED) then          		
            TitanPanelCurrencyButton_InitOnLoadedAndEntering(self);
        end
        return;
    end

    if (event == "PLAYER_MONEY" or
		event == "CURRENCY_DISPLAY_UPDATE") 
	then
        if (CURRENCY_INITIALIZED) then
			TitanPanelCurrencyButton_UpdateButtonText();
        end
        return;
    end
end

 
-- *******************************************************************************************
-- NAME: TitanPanelCurrencyButton_UpdateButtonText()
-- DESC: Updates button text, what is always visible in Titan bar.  Originally built as a
--       MoneyFrame, so we retrofit into that.
-- *******************************************************************************************
function TitanPanelCurrencyButton_UpdateButtonText()
	pp(">>>CurrencyButton_UpdateButtonText() - "..CURRENCY_SELECTED_NAME);

	-- old: show money
	MoneyFrame_Update("TitanPanelCurrencyButton", TitanPanelCurrencyButton_GetGold());
	-- hide copper + silver
	_G["TitanPanelCurrencyButtonCopperButton"]:Hide();
	_G["TitanPanelCurrencyButtonSilverButton"]:Hide();
	-- override gold
	if (CURRENCY_INITIALIZED) then
		TitanPanelCurrencyButton_FetchCurrencyQtys();
		local data = CURRENCY_DATA[CURRENCY_SELECTED_NAME];
		_G["TitanPanelCurrencyButtonGoldButton"]:SetText(data.qty);	
		_G["TitanPanelCurrencyButtonGoldButton"]:SetNormalTexture(data.icon);

		-- debug
		local texture = _G["TitanPanelCurrencyButtonGoldButton"]:GetNormalTexture();
		if (CURRENCY_SELECTED_NAME == "Gold") then
			texture:SetTexCoord(0,0.25,0,1);
		else
			texture:SetTexCoord(0,1,0,1);
		end	
			

		-- e.g. <0,0>, <0,1>, <0.25,0>, <0.25,1>
		-- Texture:GetTexCoord()
		-- local tGold = _G["TitanPanelCurrencyButtonGoldButton"]:GetNormalTexture();
		local a, b, c, d, e, f, g, h = texture:GetTexCoord();
		local ret = "";
		ret	= ">>> texture coords:";
		ret = ret.." ";
		ret = ret.."<"..a..","..b..">";
		ret = ret.." ";
		ret = ret.."<"..c..","..d..">";
		ret = ret.." ";
		ret = ret.."<"..e..","..f..">";
		ret = ret.." ";
		ret = ret.."<"..g..","..h..">";
		pp(ret);


	end
end


-- never invoked (bc xml file overrides)
function TitanPanelCurrencyButton_GetButtonText()
	pp(">>>CurrencyButton_GetButtonText(empty)");
end


-- *******************************************************************************************
-- NAME: TitanPanelCurrencyButton_FetchCurrencyQtys()
-- DESC: Refreshes currency amounts and info from system.  Populates CURRENCY_DATA{}
-- *******************************************************************************************
function TitanPanelCurrencyButton_FetchCurrencyQtys()
	pp(">>>CurrencyButton_FetchCurrencyQtys()");
	local data = {};
	
	-- for gold
	data = {};
	data.name = "Gold";
	data.qty  = floor(GetMoney("player")/10000);
	data.icon = CURRENCY_ICON_GOLD1;
	data.texture = "|T"..data.icon..":14:14:0:0:64:16:0:16:0:16|t";
	CURRENCY_DATA[data.name] = data;

	-- for other currencies
	for i=1, GetCurrencyListSize() do 
		local name, isHeader, isExpanded, isUnused, isWatched, count, icon, maximum, hasWeeklyLimit, currentWeeklyAmount, unknown = GetCurrencyListInfo(i)
		if (icon ~= nil and count > 0 and not CURRENCY_IGNORE[name]) then 
			data = {};
			data.name = name;
			data.qty = count;
			data.icon = icon;
			data.texture = "|T"..data.icon..":14|t"
			CURRENCY_DATA[data.name] = data;
		end
	end
end

function Highlight(text)
	local color = "FF00FF00";
	return "|c"..color..text.."|r";
end

-- function TitanPanelCurrencyButton_GetTooltipText0()
   -- pp(">>>CurrencyButton_GetTooltipText0()");
   -- local tooltip = "";

   -- -- gold
   -- local name = "Gold";
   -- local amount = comma(floor(GetMoney("player")/10000));
   -- local icon = CURRENCY_ICON_GOLD1;
   -- local texture = "|T"..icon..":14:14:0:0:64:16:0:16:0:16|t"; --crops 64x16 img to <0-16,0-16>
   -- --pp(">>> texture >"..texture.."<");
   -- local line = name.."--\t"..amount.." "..texture;
   -- tooltip = tooltip..line.."\n";

   -- -- other currencies
   -- for index=1, GetCurrencyListSize() do 
      -- local name, isHeader, isExpanded, isUnused, isWatched, count, icon, maximum, hasWeeklyLimit, currentWeeklyAmount, unknown = GetCurrencyListInfo(index)
      -- if (count ~= 0) and (not isUnused) and (not CURRENCY_IGNORE[name]) then
		-- local line = "";
		
		-- -- label + amount
		-- if (name == CURRENCY_SELECTED_NAME) then 
			-- -- highlight selected
			-- line = line..Highlight(name).."--".."\t"..Highlight(comma(count));
		-- else
			-- line = line..name.."--".."\t"..comma(count);
		-- end

		-- -- icon
		-- if icon~=nil then 
			-- line = line.." |T"..icon..":14|t";
		-- else pp(">> GetTooltipText(): nil icon for >"..name.."< !!!");
		-- end

		-- --local line2, k = string.gsub(line, '|', '!');
		-- --pp(line2)
		-- tooltip = tooltip..line.."\n";
      -- end
	-- end    
   
   -- return tooltip;    
-- end

-- *******************************************************************************************
-- NAME: TitanPanelCurrencyButton_GetTooltipText()
-- DESC: Gets our tool-tip text, what appears when we hover over our item on the Titan bar.
-- CALL: Called by TitanPanel registry hook
-- *******************************************************************************************
function TitanPanelCurrencyButton_GetTooltipText()
	pp(">>>CurrencyButton_GetTooltipText()");
	local tooltip = "";

	for k, name in pairs(CURRENCY_ORDER) do
		local line = "";
		local data = CURRENCY_DATA[name];
		
		-- label + amount
		if (name == CURRENCY_SELECTED_NAME) then 
			-- highlight selected
			line = line..Highlight(name).."--".."\t"..Highlight(comma(data.qty));
		else
			line = line..name.."--".."\t"..comma(data.qty);
		end
 		-- icon
		if data.icon~=nil then 
			line = line..data.texture;
		else pp(">> GetTooltipText(): nil icon for >"..name.."< !!!");
		end
		
		tooltip = tooltip..line.."\n";
	end

	return tooltip;    
end

-- |T escape code
-- |T<texture path>:displayHeight:displayWidth:displayOffX:displayOffY[:origX:origY:cropX1:cropX2:cropY1:cropY2]|t


-- *******************************************************************************************
-- NAME: TitanPanelCurrencyButton_GetGold()
-- DESC: This routines determines which gold total the ui wants (server or player) then calls it and returns it
-- *******************************************************************************************
function TitanPanelCurrencyButton_GetGold()
	--pp(">>>CurrencyButton_GetGold()");
    local ttlgold = 0;
    ttlgold = GetMoney("player");
    return ttlgold;
end


-- *******************************************************************************************
-- NAME: TitanPanelCurrencyButton_InitOnLoadedAndEntering()
-- DESC: Initialization
-- WHEN: Called on later of VARIABLES_LOADED && ENTERINGWORLD
-- *******************************************************************************************
function TitanPanelCurrencyButton_InitOnLoadedAndEntering(self)
	CURRENCY_INITIALIZED = true;
	TitanPanelCurrencyButton_UpdateButtonText();
end



-- *******************************************************************************************
-- NAME: TitanPanelRightClickMenu_PrepareCurrencyMenu
-- DESC: Builds the right click config menu
-- WHEN: Titan Panel looks for this fn - "TitanPanelRightClickMenu_Prepare<id>Menu()"
-- *******************************************************************************************
function TitanPanelRightClickMenu_PrepareCurrencyMenu()
	pp(">>>TitanPanelRightClickMenu_PrepareCurrencyMenu()");
	
	TitanPanelRightClickMenu_AddTitle(TITAN_CURRENCY_MENU_TEXT, _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);

	--TitanPanelRightClickMenu_AddSpacer();

	TitanPanelRightClickMenu_AddToggleVar("text to show", TITAN_CURRENCY_ID, "temp_var_name", nil, _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);
	
	
	-- -- Level 2
	-- if _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"] == 2 then
		-- if _G["LIB_UIDROPDOWNMENU_MENU_VALUE"] == "CoordFormat" then
			-- TitanPanelRightClickMenu_AddTitle(L["TITAN_LOCATION_FORMAT_COORD_LABEL"], _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);
			-- info = {};
			-- info.text = L["TITAN_LOCATION_FORMAT_LABEL"];
			-- info.func = function()
				-- TitanSetVar(TITAN_LOCATION_ID, "CoordsFormat1", 1);
				-- TitanSetVar(TITAN_LOCATION_ID, "CoordsFormat2", nil);
				-- TitanSetVar(TITAN_LOCATION_ID, "CoordsFormat3", nil);
				-- TitanPanelButton_UpdateButton(TITAN_LOCATION_ID);
			-- end
			-- info.checked = TitanGetVar(TITAN_LOCATION_ID, "CoordsFormat1");
			-- Lib_UIDropDownMenu_AddButton(info, _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);

			-- info = {};
			-- info.text = L["TITAN_LOCATION_FORMAT2_LABEL"];
			-- info.func = function()
				-- TitanSetVar(TITAN_LOCATION_ID, "CoordsFormat1", nil);
				-- TitanSetVar(TITAN_LOCATION_ID, "CoordsFormat2", 1);
				-- TitanSetVar(TITAN_LOCATION_ID, "CoordsFormat3", nil);
				-- TitanPanelButton_UpdateButton(TITAN_LOCATION_ID);
			-- end
			-- info.checked = TitanGetVar(TITAN_LOCATION_ID, "CoordsFormat2");
			-- Lib_UIDropDownMenu_AddButton(info, _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);

			-- info = {};
			-- info.text = L["TITAN_LOCATION_FORMAT3_LABEL"];
			-- info.func = function()
				-- TitanSetVar(TITAN_LOCATION_ID, "CoordsFormat1", nil);
				-- TitanSetVar(TITAN_LOCATION_ID, "CoordsFormat2", nil);
				-- TitanSetVar(TITAN_LOCATION_ID, "CoordsFormat3", 1);
				-- TitanPanelButton_UpdateButton(TITAN_LOCATION_ID);
			-- end
			-- info.checked = TitanGetVar(TITAN_LOCATION_ID, "CoordsFormat3");
			-- Lib_UIDropDownMenu_AddButton(info, _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);
		-- end
		-- return
	-- end
	
	
	-- -- Level 1
	-- info = {};
	-- info.notCheckable = true
	-- info.text = L["TITAN_LOCATION_FORMAT_COORD_LABEL"];
	-- info.value = "CoordFormat"
	-- info.hasArrow = 1;
	-- Lib_UIDropDownMenu_AddButton(info);

	CURRENCY_MENU_PREPARED = true;
end
	-- if LIB_UIDROPDOWNMENU_MENU_LEVEL == 1 then
		-- -- Menu title
		-- TitanPanelRightClickMenu_AddTitle(L["TITAN_GOLD_ITEMNAME"]);

		-- -- Function to toggle button gold view
		-- if TitanGetVar(TITAN_GOLD_ID, "ViewAll") then
			-- TitanPanelRightClickMenu_AddCommand(L["TITAN_GOLD_TOGGLE_PLAYER_TEXT"], TITAN_GOLD_ID,"TitanPanelGoldButton_Toggle");
		-- else
			-- TitanPanelRightClickMenu_AddCommand(L["TITAN_GOLD_TOGGLE_ALL_TEXT"], TITAN_GOLD_ID,"TitanPanelGoldButton_Toggle");
		-- end

		-- -- Function to toggle display sort
		-- if TitanGetVar(TITAN_GOLD_ID, "SortByName") then
			-- TitanPanelRightClickMenu_AddCommand(L["TITAN_GOLD_TOGGLE_SORT_GOLD"], TITAN_GOLD_ID,"TitanPanelGoldSort_Toggle");
		-- else
			-- TitanPanelRightClickMenu_AddCommand(L["TITAN_GOLD_TOGGLE_SORT_NAME"], TITAN_GOLD_ID,"TitanPanelGoldSort_Toggle");
		-- end

		-- -- Function to toggle gold per hour sort
		-- if TitanGetVar(TITAN_GOLD_ID, "DisplayGoldPerHour") then
			-- TitanPanelRightClickMenu_AddCommand(L["TITAN_GOLD_TOGGLE_GPH_HIDE"], TITAN_GOLD_ID,"TitanPanelGoldGPH_Toggle");
		-- else
			-- TitanPanelRightClickMenu_AddCommand(L["TITAN_GOLD_TOGGLE_GPH_SHOW"], TITAN_GOLD_ID,"TitanPanelGoldGPH_Toggle");
		-- end

		-- -- A blank line in the menu
		-- TitanPanelRightClickMenu_AddSpacer();

		-- local info = {};
		-- info.text = L["TITAN_GOLD_COIN_NONE"];
		-- info.checked = TitanGetVar(TITAN_GOLD_ID, "ShowCoinNone");
		-- info.func = function()
			-- ShowProperLabels("ShowCoinNone")
		-- end
		-- Lib_UIDropDownMenu_AddButton(info, _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);
		-- local info = {};
		-- info.text = L["TITAN_GOLD_COIN_LABELS"];
		-- info.checked = TitanGetVar(TITAN_GOLD_ID, "ShowCoinLabels");
		-- info.func = function()
			-- ShowProperLabels("ShowCoinLabels")
		-- end
		-- Lib_UIDropDownMenu_AddButton(info, _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);
		-- local info = {};
		-- info.text = L["TITAN_GOLD_COIN_ICONS"];
		-- info.checked = TitanGetVar(TITAN_GOLD_ID, "ShowCoinIcons");
		-- info.func = function()
			-- ShowProperLabels("ShowCoinIcons")
		-- end
		-- Lib_UIDropDownMenu_AddButton(info, _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);

		-- TitanPanelRightClickMenu_AddSpacer();

		-- local info = {};
		-- info.text = L["TITAN_USE_COMMA"];
		-- info.checked = TitanGetVar(TITAN_GOLD_ID, "UseSeperatorComma");
		-- info.func = function()
			-- Seperator("UseSeperatorComma")
		-- end
		-- Lib_UIDropDownMenu_AddButton(info, _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);
		-- local info = {};
		-- info.text = L["TITAN_USE_PERIOD"];
		-- info.checked = TitanGetVar(TITAN_GOLD_ID, "UseSeperatorPeriod");
		-- info.func = function()
			-- Seperator("UseSeperatorPeriod")
		-- end
		-- Lib_UIDropDownMenu_AddButton(info, _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);

		-- TitanPanelRightClickMenu_AddSpacer();

		-- local info = {};
		-- info.text = L["TITAN_GOLD_MERGE"];
		-- info.checked = TitanGetVar(TITAN_GOLD_ID, "MergeServers");
		-- info.func = function()
			-- Merger("MergeServers")
		-- end
		-- Lib_UIDropDownMenu_AddButton(info, _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);
		-- local info = {};
		-- info.text = L["TITAN_GOLD_SEPARATE"];
		-- info.checked = TitanGetVar(TITAN_GOLD_ID, "SeparateServers");
		-- info.func = function()
			-- Merger("SeparateServers")
		-- end
		-- Lib_UIDropDownMenu_AddButton(info, _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);

		-- TitanPanelRightClickMenu_AddSpacer();

		-- info = {};
		-- info.text = L["TITAN_GOLD_ONLY"];
		-- info.checked = TitanGetVar(TITAN_GOLD_ID, "ShowGoldOnly");
		-- info.func = function()
			-- TitanToggleVar(TITAN_GOLD_ID, "ShowGoldOnly");
			-- TitanPanelButton_UpdateButton(TITAN_GOLD_ID);
		-- end
		-- Lib_UIDropDownMenu_AddButton(info, _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);

		-- -- A blank line in the menu
		-- TitanPanelRightClickMenu_AddSpacer();

		-- -- Show toon
		-- info = {};
		-- info.notCheckable = true
		-- info.text = L["TITAN_GOLD_SHOW_PLAYER"];
		-- info.value = "ToonShow";
		-- info.hasArrow = 1;
		-- Lib_UIDropDownMenu_AddButton(info);

		-- -- Delete toon
		-- info = {};
		-- info.notCheckable = true
		-- info.text = L["TITAN_GOLD_DELETE_PLAYER"];
		-- info.value = "ToonDelete";
		-- info.hasArrow = 1;
		-- Lib_UIDropDownMenu_AddButton(info);

		-- -- A blank line in the menu
		-- TitanPanelRightClickMenu_AddSpacer();

		-- -- Function to clear the enter database
		-- info = {};
		-- info.notCheckable = true
		-- info.text = L["TITAN_GOLD_CLEAR_DATA_TEXT"];
		-- info.func = TitanGold_ClearDB;
		-- Lib_UIDropDownMenu_AddButton(info);

		-- TitanPanelRightClickMenu_AddCommand(L["TITAN_GOLD_RESET_SESS_TEXT"], TITAN_GOLD_ID, "TitanPanelGoldButton_ResetSession");

		-- -- A blank line in the menu
		-- TitanPanelRightClickMenu_AddSpacer();
		-- TitanPanelRightClickMenu_AddToggleIcon(TITAN_GOLD_ID);
		-- TitanPanelRightClickMenu_AddToggleLabelText(TITAN_GOLD_ID);
		-- TitanPanelRightClickMenu_AddToggleColoredText(TITAN_GOLD_ID);
		-- TitanPanelRightClickMenu_AddSpacer();

		-- -- Generic function to toggle and hide
		-- TitanPanelRightClickMenu_AddCommand(L["TITAN_PANEL_MENU_HIDE"], TITAN_GOLD_ID, TITAN_PANEL_MENU_FUNC_HIDE);
	-- end

	-- if LIB_UIDROPDOWNMENU_MENU_LEVEL == 2 and LIB_UIDROPDOWNMENU_MENU_VALUE == "ToonDelete" then
		-- local info = {};
		-- info.notCheckable = true
		-- info.text = L["TITAN_GOLD_FACTION_PLAYER_ALLY"];
		-- info.value = "DeleteAlliance";
		-- info.hasArrow = 1;
		-- Lib_UIDropDownMenu_AddButton(info, LIB_UIDROPDOWNMENU_MENU_LEVEL);

		-- info.text = L["TITAN_GOLD_FACTION_PLAYER_HORDE"];
		-- info.value = "DeleteHorde";
		-- info.hasArrow = 1;
		-- Lib_UIDropDownMenu_AddButton(info, LIB_UIDROPDOWNMENU_MENU_LEVEL);
	-- elseif LIB_UIDROPDOWNMENU_MENU_LEVEL == 2 and LIB_UIDROPDOWNMENU_MENU_VALUE == "ToonShow" then
		-- local info = {};
		-- info.notCheckable = true
		-- info.text = L["TITAN_GOLD_FACTION_PLAYER_ALLY"];
		-- info.value = "ShowAlliance";
		-- info.hasArrow = 1;
		-- Lib_UIDropDownMenu_AddButton(info, LIB_UIDROPDOWNMENU_MENU_LEVEL);

		-- info.text = L["TITAN_GOLD_FACTION_PLAYER_HORDE"];
		-- info.value = "ShowHorde";
		-- info.hasArrow = 1;
		-- Lib_UIDropDownMenu_AddButton(info, LIB_UIDROPDOWNMENU_MENU_LEVEL);
	-- end
		
	-- if LIB_UIDROPDOWNMENU_MENU_LEVEL == 3 and LIB_UIDROPDOWNMENU_MENU_VALUE == "DeleteAlliance" then
		-- DeleteMenuButtons("Alliance")
	-- elseif LIB_UIDROPDOWNMENU_MENU_LEVEL == 3 and LIB_UIDROPDOWNMENU_MENU_VALUE == "DeleteHorde" then
		-- DeleteMenuButtons("Horde")
	-- elseif LIB_UIDROPDOWNMENU_MENU_LEVEL == 3 and LIB_UIDROPDOWNMENU_MENU_VALUE == "ShowAlliance" then
		-- ShowMenuButtons("Alliance")
	-- elseif LIB_UIDROPDOWNMENU_MENU_LEVEL == 3 and LIB_UIDROPDOWNMENU_MENU_VALUE == "ShowHorde" then
		-- ShowMenuButtons("Horde")
	-- end
-- end


    -- returns relative coords of cropped section (0-1)
	-- e.g. <0,0>, <0.25,0>, <1,0>, <1,0.25>
	-- Texture:GetTexCoord()
	-- local tGold = _G["TitanPanelCurrencyButtonGoldButton"]:GetNormalTexture();
	-- local a, b, c, d, e, f, g, h = tGold:GetTexCoord();
	-- local ret = "";
	-- ret	= ">>> gold texture coords:";
	-- ret = ret.." ";
	-- ret = ret.."<"..a..","..b..">";
	-- ret = ret.." ";
	-- ret = ret.."<"..c..","..d..">";
	-- ret = ret.." ";
	-- ret = ret.."<"..e..","..f..">";
	-- ret = ret.." ";
	-- ret = ret.."<"..g..","..h..">";
	-- pp(ret);

	
	
