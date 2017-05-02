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
-- DESC : Register with WOW events + TitanPanel
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
			SelectedCurrency = "Gold",
		},
    };

	-- register with WOW
    self:RegisterEvent("VARIABLES_LOADED");
    self:RegisterEvent("PLAYER_ENTERING_WORLD");
    self:RegisterEvent("PLAYER_MONEY");
    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE");   
end

-- **************************************************************************
-- NAME : TitanPanelCurrencyButton_OnEvent()
-- DESC : Event handler
-- CALL : Called by WOW
-- **************************************************************************
function TitanCurrency_OnEvent(self, event, ...)
	--pp(">>> Currency event - "..event);

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
-- DESC: Updates button text, what is always visible in Titan bar.  
-- HIST: Originally built as a MoneyFrame, so we retrofit into that.
-- *******************************************************************************************
function TitanPanelCurrencyButton_UpdateButtonText()
	local selected = TitanGetVar(TITAN_CURRENCY_ID, "SelectedCurrency");
	--pp(">>>CurrencyButton_UpdateButtonText() - "..selected);
	
	-- old: show money
	MoneyFrame_Update("TitanPanelCurrencyButton", TitanPanelCurrencyButton_GetGold());
	-- hide copper + silver
	_G["TitanPanelCurrencyButtonCopperButton"]:Hide();
	_G["TitanPanelCurrencyButtonSilverButton"]:Hide();
	-- override gold
	if (CURRENCY_INITIALIZED) then
		-- reload CURRENCY_DATA{}
		TitanPanelCurrencyButton_GetCurrencyData();
		
		-- update button
		local data = CURRENCY_DATA[selected];
		_G["TitanPanelCurrencyButtonGoldButton"]:SetText(data.qty);	
		_G["TitanPanelCurrencyButtonGoldButton"]:SetNormalTexture(data.icon);

		-- retrofit MoneyFrame
		local texture = _G["TitanPanelCurrencyButtonGoldButton"]:GetNormalTexture();
		if (selected == "Gold") then
			texture:SetTexCoord(0,0.25,0,1);
		else
			texture:SetTexCoord(0,1,0,1);
		end	

		-- debug SetTexCoord()
		-- -- e.g. <0,0>, <0,1>, <0.25,0>, <0.25,1>
		-- local a, b, c, d, e, f, g, h = texture:GetTexCoord();
		-- local ret = "";
		-- ret	= ">>> texture coords:";
		-- ret = ret.." ";
		-- ret = ret.."<"..a..","..b..">";
		-- ret = ret.." ";
		-- ret = ret.."<"..c..","..d..">";
		-- ret = ret.." ";
		-- ret = ret.."<"..e..","..f..">";
		-- ret = ret.." ";
		-- ret = ret.."<"..g..","..h..">";
		-- pp(ret);
	end
end


-- never invoked (bc xml file overrides)
function TitanPanelCurrencyButton_GetButtonText()
	pp(">>>CurrencyButton_GetButtonText(empty)");
end


-- *******************************************************************************************
-- NAME: TitanPanelCurrencyButton_GetCurrencyData()
-- DESC: Refreshes currency amounts and info from system.  Populates CURRENCY_DATA{}
-- *******************************************************************************************
function TitanPanelCurrencyButton_GetCurrencyData()
	--pp(">>>CurrencyButton_FetchCurrencyQtys()");
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


-- *******************************************************************************************
-- NAME: TitanPanelCurrencyButton_GetTooltipText()
-- DESC: Gets our tool-tip text, what appears when we hover over our item on the Titan bar.
-- CALL: Called by TitanPanel registry hook
-- *******************************************************************************************
function TitanPanelCurrencyButton_GetTooltipText()
	--pp(">>>CurrencyButton_GetTooltipText()");
	local tooltip = "";

	for k, name in pairs(CURRENCY_ORDER) do
		local line = "";
		local data = CURRENCY_DATA[name];
		
		-- label + amount
		if (name == TitanGetVar(TITAN_CURRENCY_ID, "SelectedCurrency")) then 
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
	--pp(">>>TitanPanelRightClickMenu_PrepareCurrencyMenu()");
	
	-- main currency selector
	TitanPanelRightClickMenu_AddTitle("Select Main");
	for k, name in pairs(CURRENCY_ORDER) do
		info = {};
		info.text = CURRENCY_DATA[name].texture.." "..name;
		info.checked = (TitanGetVar(TITAN_CURRENCY_ID, "SelectedCurrency") == name);
		info.func = function()
			--pp("> button pushed: >"..name.."<");
			TitanSetVar(TITAN_CURRENCY_ID, "SelectedCurrency", name);
			TitanPanelButton_UpdateButton(TITAN_CURRENCY_ID);
			TitanPanelCurrencyButton_UpdateButtonText();
		end
		Lib_UIDropDownMenu_AddButton(info);
	end

	
	-- -- as nested menu
	-- -- Level 2
	-- if ( _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"] == 2 ) then
		-- if ( _G["LIB_UIDROPDOWNMENU_MENU_VALUE"] == "SelectedCurrency" ) then
			-- --TitanPanelRightClickMenu_AddTitle(LB["TITAN_CURRENCY_FORMAT_COORD_LABEL"], _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);
			-- TitanPanelRightClickMenu_AddTitle("Primary", _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);
			-- for k, name in pairs(CURRENCY_ORDER) do
				-- info = {};
				-- info.text = CURRENCY_DATA[name].texture.." "..name;
				-- info.checked = (TitanGetVar(TITAN_CURRENCY_ID, "SelectedCurrency") == name);
				-- info.func = function()
					-- pp("> button pushed: >"..name.."<");
					-- TitanSetVar(TITAN_CURRENCY_ID, "SelectedCurrency", name);
					-- TitanPanelButton_UpdateButton(TITAN_CURRENCY_ID);
					-- TitanPanelCurrencyButton_UpdateButtonText();
				-- end
				-- Lib_UIDropDownMenu_AddButton(info, _G["LIB_UIDROPDOWNMENU_MENU_LEVEL"]);
			-- end
		-- end
		-- return
	-- end
	-- -- Level 1
	-- info = {};
	-- info.notCheckable = true
	-- --info.text = L["TITAN_CURRENCY_FORMAT_COORD_LABEL"];
	-- info.text = "Main Display";
	-- info.value = "SelectedCurrency"
	-- info.hasArrow = 1;
	-- Lib_UIDropDownMenu_AddButton(info);

	CURRENCY_MENU_PREPARED = true;
end


	
	
