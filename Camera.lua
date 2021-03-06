-------------
-- GLOBALS --
-------------
assert(DynamicCam);
DynamicCam.Camera = DynamicCam:NewModule("Camera", "AceTimer-3.0", "AceHook-3.0");


------------
-- LOCALS --
------------
local Camera = DynamicCam.Camera;
local parent = DynamicCam;
local _;

local zoom = {
	set = nil,

	action = nil,
	time = nil,
	continousSpeed = 1,

	timer = nil,
	incTimer = nil,
	oldSpeed = nil,
}

local nameplateRestore = {};
local function RestoreNameplates()
	-- restore nameplates if they need to be restored
	if (not InCombatLockdown()) then
		for k,v in pairs(nameplateRestore) do
			SetCVar(k, v);
		end
		nameplateRestore = {};
	end
end


----------
-- CORE --
----------
function Camera:OnInitialize()
	-- hook camera functions to figure out wtf is happening
	self:Hook("CameraZoomIn", true);
	self:Hook("CameraZoomOut", true);

	self:Hook("MoveViewInStart", true);
	self:Hook("MoveViewInStop", true);
	self:Hook("MoveViewOutStart", true);
	self:Hook("MoveViewOutStop", true);
end


-----------
-- CVARS --
-----------
local function GetMaxZoomFactor()
	return tonumber(GetCVar("cameraDistanceMaxZoomFactor"));
end

local function GetMaxZoom()
	return 15*GetMaxZoomFactor();
end

local function GetZoomSpeed()
	return tonumber(GetCVar("cameraZoomSpeed"));
end

local function SetZoomSpeed(value)
	parent:DebugPrint("SetZoomSpeed:", value);
	SetCVar("cameraZoomSpeed", math.min(50,value));
end


---------------------
-- LOCAL FUNCTIONS --
---------------------
local function GetEstimatedZoomTime(increments)
	return increments/GetZoomSpeed();
end

local function GetEstimatedZoomSpeed(increments, time)
	return math.min(50, (increments/time));
end


-----------
-- HOOKS --
-----------
local function CameraZoomFinished(restore)
	--parent:DebugPrint("Finished zooming");

	-- restore oldSpeed if it exists
    if (restore and zoom.oldSpeed) then
        SetZoomSpeed(zoom.oldSpeed);
        zoom.oldSpeed = nil;
    end

	zoom.action = nil;
	zoom.time = nil;
	zoom.set = nil;
end

function Camera:CameraZoomIn(...)
	self:CameraZoom("in", ...);
end

function Camera:CameraZoomOut(...)
	self:CameraZoom("out", ...);
end

function Camera:CameraZoom(direction, increments, automated)
	local zoomMax = GetMaxZoom();
	increments = increments or 1;

	-- check if we were continously zooming before and stop tracking it if we were
	if (zoom.action == "continousIn") then
		self:MoveViewInStop();
	elseif (zoom.action == "continousOut") then
		self:MoveViewOutStop();
	end

	-- check if we were going in the opposite direction
	if (zoom.action and zoom.action ~= direction) then
		-- remove set point, since it doesn't matter anymore, since we canceled
		CameraZoomFinished(true);
	end

	-- set zoom.set
	local setZoom;
	if (zoom.action and zoom.action == direction and zoom.set) then
		setZoom = zoom.set;
	else
		setZoom = GetCameraZoom();
	end

	if (direction == "in") then
		-- zooming in
		zoom.set = math.max(0, setZoom - increments);
	elseif (direction == "out") then
		-- zooming out
		zoom.set = math.min(zoomMax, setZoom + increments);
	end

	-- set zoom done time
	-- (yard) / (yards/second) = seconds
	local difference = math.abs(GetCameraZoom() - zoom.set);
	local timeToZoom = GetEstimatedZoomTime(difference);
	if (difference > 0) then
		zoom.action = direction;
		-- set a timer for when it finishes
		if (zoom.incTimer) then
			self:CancelTimer(zoom.incTimer);
			zoom.incTimer = nil;
		end

		zoom.time = GetTime() + timeToZoom;
		zoom.incTimer = self:ScheduleTimer(CameraZoomFinished, timeToZoom, not automated);
	end

	-- if (increments ~= 0) then
	-- 	parent:DebugPrint(automated and "Automated" or "Manual", "Zoom", direction, "increments:", increments, "diff:", difference, "new zoom level:", zoom.set, "time:", timeToZoom);
	-- end
end

function Camera:MoveViewInStart(speed)
	zoom.action = "continousIn";
	zoom.time = GetTime();

	if (speed) then
		zoom.continousSpeed = speed;
	else
		zoom.continousSpeed = 1;
	end
end

function Camera:MoveViewInStop()
	if (zoom.action == "continousIn") then
		zoom.action = nil;
		zoom.time = nil;
	end
end

function Camera:MoveViewOutStart(speed)
	zoom.action = "continousOut";
	zoom.time = GetTime();

	if (speed) then
		zoom.continousSpeed = speed;
	else
		zoom.continousSpeed = 1;
	end
end

function Camera:MoveViewOutStop()
	if (zoom.action == "continousOut") then
		zoom.action = nil;
		zoom.time = nil;
	end
end


------------------
-- ZOOM ACTIONS --
------------------
function Camera:PrintCameraVars()
	parent:Print("Zoom info:", "curValue:", GetCameraZoom(), ((zoom.time and (zoom.time - GetTime() > 0)) and (zoom.action or "no action").." "..(zoom.time - GetTime()) or ""));
end

function Camera:IsZooming()
    local ret = false;

    -- has an active action running
	if (zoom.action and zoom.time) then
		if (zoom.time > GetTime()) then
			ret = true;
		else
			zoom.time = nil;
		end
    end

    -- has an active timer running
    if (zoom.timer) then
        -- has an active timer running
        parent:DebugPrint("Active timer running, so is zooming")
        ret = true;
	end

	return ret;
end

function Camera:StopZooming()
    -- restore oldSpeed if it exists
    if (zoom.oldSpeed) then
        SetZoomSpeed(zoom.oldSpeed);
        zoom.oldSpeed = nil;
    end

	-- has a timer waiting
	if (zoom.timer) then
		-- kill the timer
		self:CancelTimer(zoom.timer);
        parent:DebugPrint("Killing zoom timer!");
        zoom.timer = nil;
	end

	-- restore nameplates if need to
	RestoreNameplates();

	if ((zoom.action == "in" or zoom.action == "in") and zoom.time and (zoom.time > (GetTime() + .25))) then
		-- we're obviously still zooming in from an incremental zoom, cancel it
		CameraZoomOut(0, true);
		CameraZoomIn(0, true);
		zoom.action = nil;
		zoom.time = nil;
	elseif (zoom.action == "continousIn") then
		MoveViewInStop();
	elseif (zoom.action == "continousOut") then
		MoveViewOutStop();
	end
end

function Camera:SetZoom(level, time, timeIsMax)
	-- know where we are, perform just a zoom in or zoom out to level
	local difference = GetCameraZoom() - level;

	parent:DebugPrint("SetZoom", level, time, timeIsMax, "difference", difference);

	-- set zoom speed to match time
	if (difference ~= 0) then
		zoom.oldSpeed = zoom.oldSpeed or GetZoomSpeed();
		local speed = GetEstimatedZoomSpeed(math.abs(difference), time);

		if ((not timeIsMax) or (timeIsMax and (speed > zoom.oldSpeed))) then
			SetZoomSpeed(speed);

			local func = function ()
				if (zoom.oldSpeed) then
					SetZoomSpeed(zoom.oldSpeed);
					zoom.oldSpeed = nil;
					zoom.timer = nil;
				end
			end

			zoom.timer = self:ScheduleTimer(func, GetEstimatedZoomTime(math.abs(difference)));
		end
	end

	if (GetCameraZoom() > level) then
		CameraZoomIn(difference, true);
		return true;
	elseif (GetCameraZoom() < level) then
		CameraZoomOut(-difference, true);
		return true;
	end
end

function Camera:ZoomUntil(condition, continousTime, isFitting)
    if (condition) then
        local command, increments, speed = condition(isFitting);

        if (command) then
            if (speed) then
                -- set speed, StopZooming will set it back
                if (speed > GetZoomSpeed()) then
                    zoom.oldSpeed = zoom.oldSpeed or GetZoomSpeed();
                    SetZoomSpeed(speed);
                end
            end

            -- actually zoom in the direction
            if (command == "in") then
                -- if we're not already zooming out, zoom in
                if (not (zoom.action and zoom.action == "out" and zoom.time and zoom.time >= (GetTime() - .1))) then
                    CameraZoomIn(increments, true);
                end
            elseif (command == "out") then
                -- if we're not already zooming in, zoom out
               if (not (zoom.action and zoom.action == "in" and zoom.time and zoom.time >= (GetTime() - .1))) then
					CameraZoomOut(increments, true);
               end
            elseif (command == "set") then
                if (not (zoom.action and zoom.time and zoom.time >= (GetTime() - .1))) then
                    parent:DebugPrint("Nameplate setting zoom!", increments);
                    self:SetZoom(increments, .5, true); -- constant value here
                end
            end

            -- if the cammand is to wait, just setup the timer
            if (command == "wait") then
                parent:DebugPrint("Waiting on namemplate zoom");
                zoom.timer = self:ScheduleTimer("ZoomUntil", .1, condition, continousTime);
            end

            if (increments) then
                -- set a timer for when this should be called again
                zoom.timer = self:ScheduleTimer("ZoomUntil", GetEstimatedZoomTime(increments)*.75, condition, continousTime, true);
            end

            return true;
        else
            -- the condition is met
            if (zoom.oldSpeed) then
                SetZoomSpeed(zoom.oldSpeed);
                zoom.oldSpeed = nil;
            end

            -- if continously checking, then set the timer for that
            if (continousTime) then
                zoom.timer = self:ScheduleTimer("ZoomUntil", continousTime, condition, continousTime);
			else
				zoom.timer = nil;

				-- restore nameplates if they need to be restored
				RestoreNameplates();
            end

            return;
        end
	end
end


----------------------
-- ZOOM CONVENIENCE --
----------------------
function Camera:ZoomInTo(level, time, timeIsMax)
	if (GetCameraZoom() > level) then
		return self:SetZoom(level, time, timeIsMax);
	end
end

function Camera:ZoomOutTo(level, time, timeIsMax)
	if (GetCameraZoom() < level) then
		return self:SetZoom(level, time, timeIsMax);
	end
end

function Camera:ZoomToRange(minLevel, maxLevel, time, timeIsMax)
	if (GetCameraZoom() < minLevel) then
		return self:SetZoom(minLevel, time, timeIsMax);
	elseif (GetCameraZoom() > maxLevel) then
		return self:SetZoom(maxLevel, time, timeIsMax);
	end
end

function Camera:FitNameplate(zoomMin, zoomMax, increments, nameplatePosition, sensitivity, speedMultiplier, continously, toggleNameplate)
	parent:DebugPrint("Fitting Nameplate for target");

	-- create a function that returns the zoom direction or nil for stop zooming
	local condition = function(isFitting)
		local nameplate = C_NamePlate.GetNamePlateForUnit("target");

		-- we're out of the min and max
		if (GetCameraZoom() > zoomMax) then
			return "in", (GetCameraZoom() - zoomMax), 20;
		elseif (GetCameraZoom() < zoomMin) then
			return "out", (zoomMin - GetCameraZoom()), 20;
		end

		-- if the nameplate exists, then adjust
		if (nameplate) then
			local top = nameplate:GetTop();
			local screenHeight = GetScreenHeight() * UIParent:GetEffectiveScale();
			local difference = screenHeight - top;
			local ratio = (1 - difference/screenHeight) * 100;

			if (isFitting) then
				parent:DebugPrint("Fitting", "Ratio:", ratio, "Bounds:", math.max(50, nameplatePosition - sensitivity/2), math.min(94, nameplatePosition + sensitivity/2));
			else
				parent:DebugPrint("Ratio:", ratio, "Bounds:", math.max(50, nameplatePosition - sensitivity), math.min(94, nameplatePosition + sensitivity));
			end

			if (difference < 40) then
				-- we're at the top, go at top speed
				if ((GetCameraZoom() + (increments*4)) <= zoomMax) then
					return "out", increments*4, 14*speedMultiplier;
				end
			elseif (ratio > (isFitting and math.min(94, nameplatePosition + sensitivity/2) or math.min(94, nameplatePosition + sensitivity))) then
				-- we're on screen, but above the target
				if ((GetCameraZoom() + increments) <= zoomMax) then
					return "out", increments, 11*speedMultiplier;
				end
			elseif (ratio > 50 and ratio <= (isFitting and math.max(50, nameplatePosition - sensitivity/2) or math.max(50, nameplatePosition - sensitivity))) then
				-- we're on screen, "in front" of the player
				if ((GetCameraZoom() - (increments)) >= zoomMin) then
					return "in", increments, 11*speedMultiplier;
				end
			end
		else
			-- nameplate doesn't exist, toggle it on
			if (toggleNameplate and not InCombatLockdown() and not nameplateRestore["nameplateShowAll"]) then
				nameplateRestore["nameplateShowAll"] = GetCVar("nameplateShowAll");
				nameplateRestore["nameplateShowFriends"] = GetCVar("nameplateShowFriends");
				nameplateRestore["nameplateShowEnemies"] = GetCVar("nameplateShowEnemies");

				-- show nameplates
				SetCVar("nameplateShowAll", 1);
				if (UnitExists("target")) then
					if (UnitIsFriend("player", "target")) then
						SetCVar("nameplateShowFriends", 1);
					else
						SetCVar("nameplateShowEnemies", 1);
					end
				else
					SetCVar("nameplateShowFriends", 1);
					SetCVar("nameplateShowEnemies", 1);
				end
			end

			-- namemplate doesn't exist, just wait
			return "wait";
		end

		return nil;
	end

	zoom.timer = self:ScheduleTimer("ZoomUntil", .25, condition, continously and .75 or nil, true);

	return true;
end
