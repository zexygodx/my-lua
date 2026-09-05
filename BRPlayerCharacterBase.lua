local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {},
  LuaEventContainer = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = {
  Reliable = true,
  Params = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Object
  }
}
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Bool
  }
}
local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local ESpecialMovementType = import("ESpecialMovementType")
local ESpiderSwingMoveState = import("ESpiderSwingMoveState")
local ESurviveWeaponPropSlot = import("ESurviveWeaponPropSlot")
local EParachuteState = import("EParachuteState")
local EMovementMode = import("EMovementMode")
local EStateType = import("EStateType")
local ESTEPoseState = import("ESTEPoseState")
local EGameModeType = import("EGameModeType")
local STExtraGameStateBase = import("STExtraGameStateBase")
local UKismetSystemLibrary = import("KismetSystemLibrary")
local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
local MatchModeIds = require("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")

function BRPlayerCharacterBase:ctor()
end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
  print(bWriteLog and "BRPlayerCharacterBase:_PostConstruct bCanNearDeathGiveup true")
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
      print(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay Add CheckFallingDistanceComponent")
      Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
    end
  end
  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.bPositiveBlowUp = true
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", {
      AttrName = {
        "bCanSelfRescue"
      }
    }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then
    return
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  print("BRPlayerCharacterBase:OnPawnStateChange:", PawnState)
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  print(bWriteLog and "BRPlayerCharacterBase:HandleFinishedState", self.STCharacterMovement)
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfigDisable then
    local EDynamicSimpleQueryConfigDisableMask = import("EDynamicSimpleQueryConfigDisableMask")
    self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(EDynamicSimpleQueryConfigDisableMask.Bit0, true)
  end
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local GameModeType = CGameMode.GameModeType
    local GameModeID = tonumber(CGameState.GameModeID)
    local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode or GameModeType == EGameModeType.EFourInOneGameMode or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bModeIDSatisfy = not MatchModeIds[GameModeID]
    print(bWriteLog and bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:", GameModeType, GameModeID, bModeTypeSatisfy, bModeIDSatisfy)
    return bModeTypeSatisfy and bModeIDSatisfy
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if NewParachuteState == EParachuteState.PS_Opening then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
          uCurrentPlayerControl.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
        end
      elseif NewParachuteState == EParachuteState.PS_None then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.RecoverParachuteOpenParam then
          uCurrentPlayerControl.CheckParachuteOpenFeature:RecoverParachuteOpenParam()
        end
        if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
          uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
        end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  printf("BRPlayerCharacterBase:OnLanded PlayerKey:%d", self.PlayerKey)
  if self.HandleOnLanded then
    self:HandleOnLanded(-1)
  end
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
      end
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ResetCheckShowUI then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ResetCheckShowUI()
      end
    end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local uGameState = GameplayData:GetGameState()
  if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
    return uGameState.GameModeType == EGameModeType.EWarGameMode
  else
    return false
  end
end

function BRPlayerCharacterBase:BPOnRecycled()
  print(bWriteLog and string.format("%s BPOnRecycled()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:BPOnRespawned()
  print(bWriteLog and string.format("%s BPOnRespawned()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnRecycle()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnSpawn()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.AddCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local uDefaultMeshRot = FRotator(0, -90, 0)
    local uDefaultMeshRelativeLoc = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then
      self.Mesh:K2_SetRelativeRotation(uDefaultMeshRot, false, nil, false)
    end
    self:CacheInitialMeshOffset(uDefaultMeshRelativeLoc, uDefaultMeshRot)
    local vRelativeRot = self.Mesh.RelativeRotation
    local vBaseRotationOffset = self.BaseRotationOffset
    local vBaseRotation = Game:QuatToRotator(vBaseRotationOffset)
    print(bWriteLog and bWriteLog and string.format("%s ResetMeshRelativeLocationAndRotation() Mesh.RelativeRotation: %s %s %s   Pawn.BaseRotationOffset:%s %s %s ", Game:GetPlainName(self.Object), tostring(vRelativeRot.Pitch), tostring(vRelativeRot.Yaw), tostring(vRelativeRot.Roll), tostring(vBaseRotation.Pitch), tostring(vBaseRotation.Yaw), tostring(vBaseRotation.Roll)))
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged22")
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChangedNew CloseUI")
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord()
end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  local IsDS = UKismetSystemLibrary.IsDedicatedServer(self)
  if not IsDS then
    return
  end
  local MainPlayerController = self:GetPlayerControllerSafety()
  if not slua.isValid(MainPlayerController) then
    return
  end
  local CharacterAvatarComp2_BP = self.CharacterAvatarComp2_BP
  if not slua.isValid(CharacterAvatarComp2_BP) then
    return
  end
  local CommerAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local changedVehicleId = CommerAvatarDataUtil:ChangeVehicleSkinByClothes(MainPlayerController, CharacterAvatarComp2_BP)
  local ESTExtraVehicleShapeType = import("ESTExtraVehicleShapeType")
  if changedVehicleId then
    local UAvatarUtils = import("AvatarUtils")
    if UAvatarUtils.GetVehicleShapeBySkinID(changedVehicleId) == ESTExtraVehicleShapeType.VST_Horse then
      local uCurPlayerState = self:GetPlayerStateSafety()
      if slua.isValid(uCurPlayerState) then
        print(bWriteLog and "  BRPlayerCharacterBase:PreAttachedToVehicle. changedVehicleId: " .. tostring(changedVehicleId))
        uCurPlayerState:AddGeneralCount(468, 1, false)
      end
    end
  end
end

function BRPlayerCharacterBase:ParachuteJump()
  local uPlayerController = self:GetControllerSafety()
  if slua.isValid(uPlayerController) then
    if not self:GetEnsure() then
      if uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteJump and uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        uPlayerController:ReInitParachuteItem()
        uPlayerController:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump over")
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump AI JUMP over, Loc=", tostring(self:K2_GetActorLocation():ToString()))
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then
    return
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:OnMovementBaseChangedEvent %s, Base: %s -> %s", uCharacter, uOldMovementBase, uNewMovementBase))
  local MedievalCrane = self:GetMedievalCraneFromBase(uNewMovementBase)
  if MedievalCrane and MedievalCrane.AddCharacter then
    MedievalCrane:AddCharacter(self.Object)
  else
    MedievalCrane = self:GetMedievalCraneFromBase(uOldMovementBase)
    if MedievalCrane and MedievalCrane.RemoveCharacter then
      MedievalCrane:RemoveCharacter(self.Object)
    end
  end
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(Base)
  if not slua.isValid(Base) or not Base.GetOwner then
    return
  end
  local Lifter = Base:GetOwner()
  if not slua.isValid(Lifter) then
    return
  end
  if not Lifter.AddCharacter then
    return
  end
  return Lifter
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local uPlayerState = self:GetPlayerStateSafety()
  if not slua.isValid(uPlayerState) then
    return false
  end
  if uPlayerState.CanUseFlaregun == false and self:IsLocallyControlled() then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:DisplayGameTipWithMsgID(48532)
    end
  end
  return not uPlayerState.CanUseFlaregun
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
  self:HandleNearDeathGiveupRescue()
end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local uNearDeathComp = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(uNearDeathComp) and self.bCanNearDeathGiveup == true then
    local uPlayerState = self:GetPlayerStateSafety()
    if slua.isValid(uPlayerState) then
      uPlayerState:AddGeneralCount(1613, 1, false)
    end
    uNearDeathComp:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction.  actionId: " .. tostring(actionId))
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then
    log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction. IsDevelopment actionId: " .. tostring(actionId))
    self:MulticastRPC_GmPlayAction(actionId)
  end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then
    return
  end
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction.  actionId: " .. tostring(actionId))
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then
    return
  end
  local LogFilter = require("common.log_filter")
  LogFilter.SetLogTreeEnable(true)
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then
    return
  end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction. assetsArray:Num(): " .. tostring(assetsArray:Num()))
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")
  
  function loadLater()
    uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end
  
  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  print(bWriteLog and "BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall " .. tostring(bServerSyncShouldCheckPassWall))
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerEnterCarryBoxState Role:%s PlayerKey:%s Name:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState Role:%s PlayerKey:%s Name:%s bInIsInterrupt:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName), tostring(bInIsInterrupt)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

function BRPlayerCharacterBase:SetAreaID(AreaID)
  self:SetAttrValue("AreaID", AreaID, -1)
end

function BRPlayerCharacterBase:GetAreaID()
  return math.floor(self:GetAttrValue("AreaID") + 0.5)
end

function BRPlayerCharacterBase:CannotChangeIntoPetSpectator()
  print(bWriteLog and "BRPlayerCharacterBase:CannotChangeIntoPetSpectator")
  return self.bCannotChangeIntoPetSpectator
end

function BRPlayerCharacterBase:DoModChangeToBT()
  print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s", tostring(self.PlayerKey)))
  if self:HasState(EPawnState.SpecialSuit) then
    self:TriggerEntrySkillWithID(4301101, true)
    print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s, HasState(EPawnState.SpecialSuit)", tostring(self.PlayerKey)))
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening")
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling")
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToNormal")
  self.Super:SwitchCameraToNormal()
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
    self.ParachuteFormation:OnLandingClearFormationCamera()
  end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local Weapon = self:GetWeaponBySlot(Slot)
    if slua.isValid(Weapon) then
      local WeaponID = Weapon:GetWeaponID()
      local AttachToOtherConfig = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if AttachToOtherConfig and AttachToOtherConfig.CheckIsWeaponInBlackList and AttachToOtherConfig.CheckIsWeaponInBlackList(WeaponID) then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck not allow switch weapon in AttachToOther, WeaponID: " .. tostring(WeaponID))
        local uPlayerController = self:GetPlayerControllerSafety()
        if Client and slua.isValid(uPlayerController) and uPlayerController.Role == ENetRole.ROLE_AutonomousProxy then
          uPlayerController:DisplayGameTipWithMsgID(47306)
        end
        return false
      end
    end
  end
  if self:HasState(EPawnState.WebSwing) and Slot ~= ESurviveWeaponPropSlot.SWPS_None and slua.isValid(self.STCharacterMovement) then
    local SpiderSwingObj = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
    if slua.isValid(SpiderSwingObj) then
      local nCurState = SpiderSwingObj:GetCurMoveState()
      if nCurState == ESpiderSwingMoveState.Launching or nCurState == ESpiderSwingMoveState.Swinging then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck blocked by SpiderSwing state: " .. tostring(nCurState))
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

-- ==============================================================================
-- ============================ MULAI AWAL FULL LOGIC MOD ==========================
-- ==============================================================================

local function Notify(msg) local s = "[VENUS VIP New] " .. tostring(msg)
pcall(function() if _G.ZEXYGODXNotify then _G.ZEXYGODXNotify(s) end end)
pcall(function() local sh = import("ScriptHelperClient") if sh and
sh.AddOnScreenDebugMessage then sh.AddOnScreenDebugMessage(s, -1, 3.0, {R=1,
G=1, B=0, A=1}, {X=1.2, Y=1.2}) end end) print(s) end

local _slua = rawget(_G, "slua")

local function Valid(obj) if not obj then return false end if _slua and
_slua.isValid then local ok, v = pcall(_slua.isValid, obj) if not ok or not v
then return false end end return true end

-- ========================================== 
-- STATIC VARIABLES & GLOBAL CACHE MAKSIMAL OPTIMASI KAN (ANTI LAG)
-- ========================================== 
local C_GREEN = {R=0, G=255, B=0, A=255}
local C_RED = {R=255, G=0, B=0, A=255}
local C_CYAN = {R=0, G=255, B=255, A=255}
local C_YELLOW = {R=255, G=255, B=0, A=255}
local C_WHITE = {R=255, G=255, B=255, A=255}
local C_BLUE_TEXT = {R=0, G=200, B=255, A=255}
local SCALE_COLOR_V2 = {R=3, G=3, B=0, A=0}

local GLOBAL_BONE_LIST = {
    "head", "neck_01", "pelvis",
    "upperarm_r", "lowerarm_r", "hand_r",
    "upperarm_l", "lowerarm_l", "hand_l",
    "thigh_l", "calf_l", "foot_l",
    "thigh_r", "calf_r", "foot_r"
}

local GLOBAL_CONNECTIONS = {
    {"neck_01", "pelvis", C_YELLOW},
    {"neck_01", "upperarm_l", C_CYAN}, {"upperarm_l", "lowerarm_l", C_CYAN}, {"lowerarm_l", "hand_l", C_CYAN},
    {"neck_01", "upperarm_r", C_CYAN}, {"upperarm_r", "lowerarm_r", C_CYAN}, {"lowerarm_r", "hand_r", C_CYAN},
    {"pelvis", "thigh_l", C_CYAN}, {"thigh_l", "calf_l", C_CYAN}, {"calf_l", "foot_l", C_CYAN},
    {"pelvis", "thigh_r", C_CYAN}, {"thigh_r", "calf_r", C_CYAN}, {"calf_r", "foot_r", C_CYAN}
}

-- ========================================== 
-- KONFIGURASI KONFIGURASI ZEXYGODX CORE + FULL FEATURES VIP 
-- ========================================== 
_G.ZEXYGODXConfig = _G.ZEXYGODXConfig or { 
    FakeHWID = false,
    CustomMagicBullet = false,
    AutoHead = false, 
    EspVip = false, 
    EspDistance = false, 
    EspVipPro = false, 
    EspRadar = false, 
    EspLoai5 = false, 
    EspLoai6 = false, 
    EspLoai7 = false,
    Esp7_SoLuong = true, -- [TAMBAH BARU] Aktifkan nonaktifkan Jumlah jumlah musuh
    Esp7_VuKhi = true,   -- [TAMBAH BARU] Aktifkan nonaktifkan Senjata senjata musuh
    Esp7_TuThe = true,   -- [TAMBAH BARU] Aktifkan nonaktifkan Posisi posisi musuh
    EspLoai8 = false,
    EspLoai9 = false, -- Saklar saklar TOTAL ESP Jenis 9
    Esp9_Count = true,    -- Hitung pemain (RedBox)
    Esp9_Name = true,     -- Nama
    Esp9_HP = true,       -- Thanh HP
    Esp9_Team = true,     -- KOTAK warna Team
    Esp9_Weapon = true,   -- Icon Senjata
    Esp9_Distance = true, -- Jarak jarak
    Esp9_Line = true,     -- Garis Line
    Esp9_Skeleton = true, -- Skeleton (Khung tulang)
    EspBomMaster = false, 
    EspItemBom = false,   
    EspActiveBom = false, 
    EspAimWarning = false,         -- [TAMBAH BARU] Saklar saklar Peringatan peringatan musuh bidik
    EspAimWarningVisCheck = false, -- [TAMBAH BARU] Saklar saklar Check dinding cho peringatan peringatan bidik
    EspVehicle = false,   
    EspVeh_Dacia = true,  
    EspVeh_UAZ = true,    
    EspVeh_Buggy = true,  
    EspVeh_Coupe = true,  
    EspVeh_Mirado = true, 
    EspVeh_Motor = true,  
    EspVeh_Other = true,  
    Esp3ShowName = true,
    Esp3ShowHP = true,
    EspAntenna = false, 
    EspOutline = false, 
    OutlineThickness = 10, 
    UnlockFPS = false, 
    IpadView = false, 
    IpadViewVehicle = false, 
    IpadViewScope = false, -- [TAMBAH BARU] Ipad View Buka Scope
    CustomAimbot = false, 
    CustomAimbotClose = false, 
    CustomHRecoil = false,  
    CustomVRecoil = false,  
    LessShake = false, 
    RemoveGrass = false, 
    RemoveTrees = false,  
    RemoveFog = false, 
    WhiteBody = false, 
    ColorBodyV2 = false,    
    ColorBodyV3 = false,    
    WallXuyenTuong = false, 
    ColorBodyNew = false,   -- [TAMBAH BARU] Saklar saklar Wall Warna New
    WallVehicle = false,  
    EspItem_Master = false, 
    EspItem_AR = true,      
    EspItem_Sniper = true,  
    EspItem_SMG = true,     
    EspItem_Shotgun = true, 
    EspItem_LMG = true,       -- [TAMBAH] Senjata senapan
    EspItem_Pistol = true,    -- [TAMBAH] Senjata pistol
    EspItem_Melee = false,    -- [TAMBAH] Jarak dekat
    EspItem_Special = true,   -- [TAMBAH] Senjata senjata khusus khusus
    EspItem_Scope = true,   
    EspItem_Grenade = true,   -- [TAMBAH] Granat peluru
    EspItem_Med = true,       -- [TAMBAH] HP & Air (Item item y medis)
    Crosshair = false,
    Accuracy = false,
    GodMode = false, 
    WallClimb = false,
    FastCar = false,
    BlackSky = false, -- Integrasi gabungan BlackSky
    
    -- Config Baru Cho Aimbot V2 (Aim Touch)
    AimTouchEnable = false,
    AimTouchHipIgKnock = false,
    AimTouchHipIgBot = false,
    AimTouchSGIgKnock = false,
    AimTouchSGIgBot = false,
    AimTouchHipVisCheck = false,
    AimTouchSGVisCheck = false,
    AimTouchHipfire = false,
    AimTouchSG = false,
    AimTouchSGAutoFire = false,
    AimTouchScopeAll = false,
    AimTouchScopeIgKnock = false,
    AimTouchScopeIgBot = false,
    AimTouchScopeVisCheck = false,
    AimTouchScopeSniper = false,
    AimTouchSniperIgKnock = false,
    AimTouchSniperIgBot = false,
    AimTouchSniperVisCheck = false,
    AimTouchMortar = false, -- [TAMBAH BARU] Aktifkan/Nonaktifkan Aimbot Senjata Mortir
    EspFovCircle = false,
    
    -- Config Mod Skin VIP
    ModEmote = false,       -- [TAMBAH BARU] Saklar saklar Mod Emote Aksi Aksi
    ModSkin = false,           
    SkinDeadBox = false,   
    SkinAttachment = false, -- [TAMBAH BARU] Saklar saklar Skin Aksesori Aksesori
    SkinOptionOpen = false,
    SkinOpenLink = false,  
    KillMessage = false,    -- [TAMBAH BARU] Saklar saklar Kill Messenger
    KillCountUI = false,    -- [TAMBAH BARU] Saklar saklar Paket Hitung Kill Count
    
    -- Toggles Aktifkan/Nonaktifkan masing-masing khusus setiap item
    SkinEnable_Suit = false, SkinEnable_Top = false, SkinEnable_Gloves = false,
    SkinEnable_Bottom = false, SkinEnable_Shoes = false, SkinEnable_Bag = false, SkinEnable_Helmet = false, SkinEnable_Parachute = false,
    SkinEnable_M416 = false, SkinEnable_AKM = false, SkinEnable_SCAR = false, SkinEnable_M762 = false,
    SkinEnable_AUG = false, SkinEnable_UMP = false, SkinEnable_UZI = false, SkinEnable_Groza = false,
    SkinEnable_S12K = false, SkinEnable_DBS = false,
    SkinEnable_Dacia = false, SkinEnable_UAZ = false, SkinEnable_Coupe = false, SkinEnable_Buggy = false, SkinEnable_Mirado = false,
    
    -- Config Glow Senjata
    WeaponGlow = false,
    
    -- Config Bug Layar
    BugManEnable = false
}

-- BERISI STATE SISTEM SISTEM SUDAH TELAH MAKSIMAL OPTIMASI KAN SEPENUHNYA TOTAL RAM KOSONG
_G.ZEXYGODXState = _G.ZEXYGODXState or { 
    LoopToken = 0, 
    NativeESPReady = false,
    GraphicsUnlocked = false, 
    MenuStep = 0, 
    LastCmdTime = 0,
    TrackedMarks = {},
    EnemyMarks = {},
    LastAimbotCheckTime = 0, 
    CustomTextData = nil,     
    LastAimbotConfigString = "",
    MagicUpdateVersion = 1,
    LastMagicConfigHash = "",
    PrevGraphicsState = {}
}

local limitTime = os.time({ year = 2026, month = 9, day = 9, hour = 23, min = 59, sec = 0 })
local currentTime = os.time(os.date("!*t"))
local isExpired = false

pcall(function()
    local fileName = ".sys_time_cache" -- Nama file tersembunyi
    local paths = {
        -- ==========================================
        -- [ANDROID] DIREKTORI DIREKTORI SAVEGAMES (Semua semua versi versi)
        -- ==========================================
        "//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        
        -- ==========================================
        -- [ANDROID] DIREKTORI DIREKTORI GAMELET/LOGS (Sembunyikan dalam anti hapus)
        -- ==========================================
        "//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,

        -- ==========================================
        -- [IOS / FALLBACK] Jalur path Sandbox Engine UE4
        -- ==========================================
        "Documents/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "Documents/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "/Documents/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "/Documents/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "../../ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "../../ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName
    }
    
    -- [IOS KHUSUS KHUSUS] Cari cari direktori direktori HOME sebenarnya medis
    if os and os.getenv then
        local homeDir = os.getenv("HOME")
        if homeDir and homeDir ~= "" then
            table.insert(paths, 1, homeDir .. "/Documents/ShadowTrackerExtra/Saved/SaveGames/" .. fileName)
            table.insert(paths, 2, homeDir .. "/Documents/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName)
        end
    end
    
    -- LAPISAN KEAMANAN KEAMANAN 1: Ambil waktu gian sebenarnya dari Server Game (Anti-ubah waktu perangkat terkena)
    local tm = package.loaded["client.logic.common.TimeManager"]
    if not tm then 
        local s, r = pcall(require, "client.logic.common.TimeManager")
        if s and r then tm = r end
    end
    if tm and type(tm.GetServerTime) == "function" then
        local serverTime = tm.GetServerTime()
        if serverTime and serverTime > 1700000000 then 
            currentTime = serverTime -- Prioritaskan prioritas waktu Server
        end
    end

    -- LAPISAN KEAMANAN KEAMANAN 2: Baca SEMUA SEMUA file tersembunyi di SaveGames dan Gamelet/logs (cari timestamp waktu gian terbesar terbesar)
    local lastSeenTime = 0
    for _, path in ipairs(paths) do
        local file = io.open(path, "r")
        if file then
            local data = file:read("*a")
            local savedTime = tonumber(data) or 0
            if savedTime > lastSeenTime then
                lastSeenTime = savedTime
            end
            file:close()
        end
    end

    if currentTime < lastSeenTime then
        -- KHI TERKENA MUNDUR HARI ATAU UBAH WAKTU PERANGKAT: Ambil lagi timestamp waktu gian sudah tersimpan terbesar terbesar
        currentTime = lastSeenTime
    else
        -- SEBAR FILE TERSEMBUNYI: Simpan perbarui perbarui waktu gian baru terbesar ke SEMUA SEMUA beberapa direktori direktori ada bisa ghi dapat
        for _, path in ipairs(paths) do
            -- Fungsi io.open("w") akan otomatis bergerak abaikan qua jika jalur path direktori direktori itu tidak ada di di senapan
            local file = io.open(path, "w")
            if file then
                file:write(tostring(currentTime))
                file:close()
            end
        end
    end
end)

isExpired = (currentTime > limitTime)



-- ========================================== 
-- FUNGSI KELOLA KELOLA BERSIHKAN SAMPAH MAP MARK (ANTI LAG/TAMPILKAN TAMPILAN VIRTUAL MUSUH MATI)
-- ========================================== 
local function SafeAddMark(id, pos, z, str, size, actor)
    local mark = nil
    pcall(function()
        local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
        if InGameMarkTools and InGameMarkTools.ClientAddMapMark then
            mark = InGameMarkTools.ClientAddMapMark(id, pos, z, str, size, actor)
            if mark then _G.ZEXYGODXState.TrackedMarks[mark] = true end
        end
    end)
    return mark
end

local function SafeRemoveMark(mark)
    if not mark then return end
    pcall(function()
        local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
        if InGameMarkTools and InGameMarkTools.HideMapMark then
            InGameMarkTools.HideMapMark(mark)
        end
        if InGameMarkTools and InGameMarkTools.RemoveMapMark then
            InGameMarkTools.RemoveMapMark(mark)
        end
    end)
    _G.ZEXYGODXState.TrackedMarks[mark] = nil
end

-- ========================================== 
-- BUAT ID DUY TERBANYAK DAN PERMANEN PERMANEN CHO SETIAP MUSUH MUSUH (PERBAIKI ERROR LAG LAG KHI SLUA BUAT WRAPPER BARU)
-- ==========================================
local function GetSafeEnemyKey(enemy)
    if Valid(enemy) then
        if enemy.PlayerKey then return tostring(enemy.PlayerKey) end
        if type(enemy.GetUniqueID) == "function" then return tostring(enemy:GetUniqueID()) end
    end
    return tostring(enemy)
end

-- ========================================== 
-- CEK TRA KLASIFIKASI KHUSUS AI (BOT) / REAL PLAYER - OPTIMIZED
-- ==========================================
local function CheckIsAI(pawn, markData)
    if markData.AK_IS_BOT ~= nil then return markData.AK_IS_BOT, true end
    
    local isAI = false
    local hasChecked = false
    pcall(function()
        if pawn.bIsAI == true or pawn.IsAI == true then isAI = true; hasChecked = true end
        if type(pawn.IsBot) == "function" and pawn:IsBot() then isAI = true; hasChecked = true end
        
        local pState = pawn.PlayerState or (type(pawn.GetPlayerState) == "function" and pawn:GetPlayerState())
        if Valid(pState) then
            hasChecked = true
            if pState.bIsABot == true or pState.bIsBot == true then isAI = true end
            if type(pState.IsBot) == "function" and pState:IsBot() then isAI = true end
        end
        
        if not isAI then
            local name = pawn.PlayerName or (type(pawn.GetPlayerName) == "function" and pawn:GetPlayerName()) or ""
            if name ~= "" and (name:find("Cobra") or name:find("Target") or name:find("bot_") or name:find("b_")) then
                isAI = true
                hasChecked = true
            end
        end
    end)
    if hasChecked then markData.AK_IS_BOT = isAI end
    return isAI, hasChecked
end



-- ========================================== 
-- SISTEM SISTEM SIMPAN DAN MUAT SETTING MENU VIP (OTOMATIS OTOMATIS)
-- ========================================== 
local function GetConfigPaths(fileName)
    local paths = {
        "//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "/Documents/ShadowTrackerExtra/Saved/Paks/puffer_temp/" .. fileName,
        "/com.tencent.ig/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "/com.vng.pubgmobile/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "/com.pubg.krmobile/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "/com.rekoo.pubgm/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "/com.pubg.imobile/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "../../ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "../../../ShadowTrackerExtra/Saved/Paks/" .. fileName,
        "../../../../ShadowTrackerExtra/Saved/Paks/" .. fileName,
        fileName
    }
    pcall(function()
        if os and os.getenv then
            local homeDir = os.getenv("HOME")
            if homeDir and homeDir ~= "" then
                table.insert(paths, 1, homeDir .. "/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName)
                table.insert(paths, 2, homeDir .. "/Documents/ShadowTrackerExtra/Saved/Paks/puffer_temp/" .. fileName)
            end
        end
    end)
    return paths
end

local ConfigFileName = "venus_settings.txt"
_G.LastConfigSaveStr = ""

-- FUNGSI SIMPAN CONFIG
_G.SaveModSettings = function()
    pcall(function()
        local data = "return {\nZEXYGODXConfig = {\n"
        for k, v in pairs(_G.ZEXYGODXConfig or {}) do
            data = data .. "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
        end
        data = data .. "},\nCustomTextData = {\n"
        if _G.ZEXYGODXState and _G.ZEXYGODXState.CustomTextData then
            for k, v in pairs(_G.ZEXYGODXState.CustomTextData) do
                data = data .. "  [\"" .. tostring(k) .. "\"] = " .. tostring(v) .. ",\n"
            end
        end
        data = data .. "}\n}"
        
        -- Anti lag lag: Hanya lanjut jalankan ghi file jika anda ada thay ubah konfigurasi konfigurasi
        if data == _G.LastConfigSaveStr then return end
        _G.LastConfigSaveStr = data

        local paths = GetConfigPaths(ConfigFileName)
        for _, path in ipairs(paths) do
            local file = io.open(path, "w")
            if file then
                file:write(data)
                file:close()
                break
            end
        end
    end)
end

-- FUNGSI MUAT (BACA) CONFIG
_G.LoadModSettings = function()
    pcall(function()
        local paths = GetConfigPaths(ConfigFileName)
        local content = nil
        for _, path in ipairs(paths) do
            local file = io.open(path, "r")
            if file then
                content = file:read("*a")
                file:close()
                break
            end
        end

        if content then
            local func = load(content)
            if func then
                local savedData = func()
                if savedData and type(savedData) == "table" then
                    if savedData.ZEXYGODXConfig then
                        for k, v in pairs(savedData.ZEXYGODXConfig) do
                            _G.ZEXYGODXConfig[k] = v
                        end
                    end
                    if savedData.CustomTextData then
                        _G.ZEXYGODXState.CustomTextData = _G.ZEXYGODXState.CustomTextData or {}
                        for k, v in pairs(savedData.CustomTextData) do
                            _G.ZEXYGODXState.CustomTextData[k] = v
                        end
                    end
                end
            end
        end
        -- Ghi ingat konfigurasi konfigurasi baru saja muat
        _G.SaveModSettings() 
    end)
end

-- LOOP ULANG CEK TRA UNTUK SIMPAN BERJALAN LATAR SANGAT RINGAN
local function AutoSaveLoop()
    pcall(function() if _G.SaveModSettings then _G.SaveModSettings() end end)
    pcall(function()
        local okTicker, ticker = pcall(require, "common.time_ticker") 
        if okTicker and ticker and ticker.AddTimerOnce then 
            ticker.AddTimerOnce(3.0, AutoSaveLoop) -- Setiap 3 detik check 1 kali
        end
    end)
end

-- MULAI BERJALAN PERTAMA AWAL PERTAMA
if not _G.ModConfigLoaded then
    _G.LoadModSettings()
    AutoSaveLoop()
    _G.ModConfigLoaded = true
end

-- BERLEBIH BERLEBIH UNTUK TIDAK TERKENA ERROR LOOP ULANG LAMA MILIK ANDA
_G.ReadLiveConfig = function()
    if _G.SaveModSettings then _G.SaveModSettings() end
end

-- ========================================== 
-- SISTEM SISTEM MENU VIP NATIVE (BERJALAN LANGSUNG LANJUT DARI SETTING GAME)
-- ========================================== 

function _G.InitModMenuTab()
    if _G.ModMenuInitialized then return end
    _G.ModMenuInitialized = true

    -- Fungsi bantu dukungan terjemahan bahasa bahasa (Otomatis bergerak pilih EN atau VN)
    local function T(vnText, enText)
        return _G.ZEXYGODXLang == "EN" and enText or vnText
    end

    _G.ZEXYGODXState.CustomTextData = _G.ZEXYGODXState.CustomTextData or {
        OuterSpeed = 10, InnerSpeed = 10, OuterRecoil = 0, HRecoil = 0.25, VRecoil = 0.25, MagicHead = 1.0, MagicBody = 1.0, MagicLegs = 1.0, IpadViewFOV = 120, IpadViewVehicleFOV = 120, IpadViewScopeFOV = 60,
        AimTouchHipPrio = 1, AimTouchHipBone = 1, AimTouchHipCond = 1, AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250,
        AimTouchSGPrio = 1, AimTouchSGBone = 2, AimTouchSGCond = 1, AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30,
        AimTouchScopePrio = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1, AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300, AimTouchScopePred = 0, AimTouchScopeRecoil = 0,
        AimTouchSniperPrio = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2, AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400, AimTouchSniperPred = 0,
        AimTouchMortarPred = 0,
        AimTouchMortarFOV = 360, -- [TAMBAH BARU] Lingkaran FOV cho Mortir
        AimTouchHipFOVColor = 7, AimTouchSGFOVColor = 1, AimTouchScopeFOVColor = 6, AimTouchSniperFOVColor = 4, AimTouchMortarFOVColor = 5, -- Variabel warna FOV masing-masing
        BugManRatio = 133,
        FastCarSpeed = 2000,
        WeaponGlowThickness = 3, WeaponGlowColor = 5,
        ColorV3Hidden = 1, ColorV3Visible = 2, ColorV3Thickness = 4, OutlineColor = 4,
        EspFovCircle_Color = 7,
        Esp9_LineThick = 1, Esp9_LineVisColor = 2, Esp9_LineHidColor = 1,
        Esp9_SkelThick = 1, Esp9_SkelVisColor = 2, Esp9_SkelHidColor = 1
    }

    local LocUtil = _G.LocUtil
    if not LocUtil and package.loaded["client.common.LocUtil"] then
        LocUtil = require("client.common.LocUtil")
    end
    
    -- 1. BUAT TABEL ID VIRTUAL DENGAN TEXT BARU (Dukung dukungan 2 bahasa bahasa)
    local FakeTextMap = {
        [999000] = T("GODMOD", "@zexygodx"),
        [999001] = T("ESP"),
        [999002] = T("MB & RECOIL"),
        [999003] = T("AIM JEMBUT"),
        [999004] = T("FITUR TAMBAHAN")
        
     
    }

    -- 2. HOOK TOTAL PAKET FUNGSI BACA TEXT MILIK GAME (FIX ERROR KOSONG THANH TAB)
    if LocUtil and not LocUtil._IsModMenuHooked_V2 then
        local hookFuncs = {"GetLocalizeResStr", "GetText", "GetTextByID", "GetLocalText", "GetLocalizeStr"}
        for _, funcName in ipairs(hookFuncs) do
            if LocUtil[funcName] then
                local old_func = LocUtil[funcName]
                LocUtil[funcName] = function(id)
                    if FakeTextMap[id] then
                        return FakeTextMap[id]
                    end
                    if type(id) == "string" and not tonumber(id) then
                        return id
                    end
                    if old_func then
                        return old_func(id)
                    end
                    return ""
                end
            end
        end
        LocUtil._IsModMenuHooked_V2 = true
    end

    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")
    
    if not SettingPageDefine.ModMenu then
        local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")
        
        local StackESP = {
            { Key = "ModMenu_ESP4", UI = AliasMap.TitleSwitcher, Text = T("ESP Radar 360", "ESP Radar 360"), GetFunc = function() return _G.ZEXYGODXConfig.EspRadar end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspRadar = v return true end },
            { Key = "ModMenu_ESP5", UI = AliasMap.TitleSwitcher, Text = T("ESP Khung Box", "ESP Box"), GetFunc = function() return _G.ZEXYGODXConfig.EspLoai5 end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspLoai5 = v return true end },
            
            
            { Key = "ModMenu_ESP7", UI = AliasMap.TitleSwitcher, Text = T("ESP Total Jumlah Musuh Xung Quanh", "ESP Enemy Count Around"), GetFunc = function() return _G.ZEXYGODXConfig.EspLoai7 end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspLoai7 = v return true end },
            
            
            
            { Key = "ModMenu_ESP8", UI = AliasMap.TitleSwitcher, Text = T("ESP Thanh HP", "ESP HP Bar"), GetFunc = function() return _G.ZEXYGODXConfig.EspLoai8 end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspLoai8 = v return true end },
            
            
            
            { Key = "ModMenu_EspItem_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ ESP Item Item (Di bawah 70m)", "▶ Item ESP (Under 70m)"), ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.EspItem_Master end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspItem_Master = v return true end },
            { Key = "ModMenu_EspItem_AR", UI = AliasMap.Switcher, Text = T("   Tampilkan Senjata AR", "   Show AR Weapons"), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspItem_AR end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspItem_AR = v return true end },
            { Key = "ModMenu_EspItem_Sniper", UI = AliasMap.Switcher, Text = T("   Tampilkan Senjata Bidik", "   Show Sniper Rifles"), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspItem_Sniper end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspItem_Sniper = v return true end },
            { Key = "ModMenu_EspItem_SMG", UI = AliasMap.Switcher, Text = T("   Tampilkan Senjata SMG", "   Show SMGs"), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspItem_SMG end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspItem_SMG = v return true end },
            { Key = "ModMenu_EspItem_Shotgun", UI = AliasMap.Switcher, Text = T("   Tampilkan Shotgun", "   Show Shotguns"), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspItem_Shotgun end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspItem_Shotgun = v return true end },
            { Key = "ModMenu_EspItem_LMG", UI = AliasMap.Switcher, Text = T("   Tampilkan Senjata Senapan LMG", "   Show LMGs"), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspItem_LMG end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspItem_LMG = v return true end },
            { Key = "ModMenu_EspItem_Pistol", UI = AliasMap.Switcher, Text = T("   Tampilkan Senjata Pistol / Flare", "   Show Pistols / Flares"), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspItem_Pistol end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspItem_Pistol = v return true end },
            { Key = "ModMenu_EspItem_Melee", UI = AliasMap.Switcher, Text = T("   Tampilkan Jarak Tempur", "   Show Melee Weapons"), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspItem_Melee end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspItem_Melee = v return true end },
            { Key = "ModMenu_EspItem_Special", UI = AliasMap.Switcher, Text = T("   Tampilkan Senjata Senjata Khusus Khusus", "   Show Special Weapons"), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspItem_Special end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspItem_Special = v return true end },
            { Key = "ModMenu_EspItem_Scope", UI = AliasMap.Switcher, Text = T("   Tampilkan Scope Bidik", "   Show Scopes"), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspItem_Scope end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspItem_Scope = v return true end },
            { Key = "ModMenu_EspItem_Grenade", UI = AliasMap.Switcher, Text = T("   Tampilkan Granat Peluru", "   Show Grenades"), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspItem_Grenade end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspItem_Grenade = v return true end },
            { Key = "ModMenu_EspItem_Med", UI = AliasMap.Switcher, Text = T("   Tampilkan HP & Air (Y Medis)", "   Show Medkits/Boosters"), ExpandHandle = "ModMenu_EspItem_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspItem_Med end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspItem_Med = v return true end },
            
            { Key = "ModMenu_ESPBom_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Peringatan Peringatan & Pelacak Posisi Bom", "▶ Grenade Warning & Tracker"), ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.EspBomMaster end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspBomMaster = v return true end },
            { Key = "ModMenu_ESPItemBom", UI = AliasMap.Switcher, Text = T("   Pelacak Posisi Item Item Bom Di bawah Tanah", "   Show Grenades On Ground"), ExpandHandle = "ModMenu_ESPBom_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspItemBom end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspItemBom = v return true end },
            { Key = "ModMenu_ESPActiveBom", UI = AliasMap.Switcher, Text = T("   Peringatan Peringatan Musuh Memegang & Melempar Bom", "   Active Grenade Warning"), ExpandHandle = "ModMenu_ESPBom_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspActiveBom end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspActiveBom = v return true end },
            
            -- [TAMBAH BARU] MENU PERINGATAN PERINGATAN MUSUH BIDIK
            { Key = "ModMenu_EspAimWarning_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Peringatan Peringatan Musuh Bidik Tembak", "▶ Enemy Aim Warning"), ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.EspAimWarning end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspAimWarning = v return true end },
            { Key = "ModMenu_EspAimWarning_Vis", UI = AliasMap.Switcher, Text = T("   Check Dinding (Hanya peringatan khi terlihat terlihat)", "   Visibility Check"), ExpandHandle = "ModMenu_EspAimWarning_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspAimWarningVisCheck end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspAimWarningVisCheck = v return true end },
            
            { Key = "ModMenu_ESPVehicle_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ ESP Pelacak Posisi Xe", "▶ Vehicle ESP"), ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.EspVehicle end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspVehicle = v return true end },
            { Key = "ModMenu_ESPVeh_Dacia", UI = AliasMap.Switcher, Text = T("   Tampilkan Xe Con (Dacia)", "   Show Dacia"), ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspVeh_Dacia end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspVeh_Dacia = v return true end },
            { Key = "ModMenu_ESPVeh_UAZ", UI = AliasMap.Switcher, Text = T("   Tampilkan Xe Jeep (UAZ)", "   Show UAZ"), ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspVeh_UAZ end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspVeh_UAZ = v return true end },
            { Key = "ModMenu_ESPVeh_Buggy", UI = AliasMap.Switcher, Text = T("   Tampilkan Xe Buggy", "   Show Buggy"), ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspVeh_Buggy end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspVeh_Buggy = v return true end },
            { Key = "ModMenu_ESPVeh_Coupe", UI = AliasMap.Switcher, Text = T("   Tampilkan Xe Bentuk Thao (Coupe RB)", "   Show Coupe RB"), ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspVeh_Coupe end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspVeh_Coupe = v return true end },
            { Key = "ModMenu_ESPVeh_Mirado", UI = AliasMap.Switcher, Text = T("   Tampilkan Xe Mirado", "   Show Mirado"), ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspVeh_Mirado end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspVeh_Mirado = v return true end },
            { Key = "ModMenu_ESPVeh_Motor", UI = AliasMap.Switcher, Text = T("   Tampilkan Xe Senapan (Motor/Scooter)", "   Show Motorcycles"), ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspVeh_Motor end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspVeh_Motor = v return true end },
            { Key = "ModMenu_ESPVeh_Other", UI = AliasMap.Switcher, Text = T("   Tampilkan Xe Lainnya (Perahu/BRDM...)", "   Show Others (Boat/BRDM)"), ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.ZEXYGODXConfig.EspVeh_Other end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspVeh_Other = v return true end },
            
            
            { Key = "ModMenu_ESPOutline_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ ESP Outline Musuh (Aktifkan HDR akan terang)", "▶ Outline ESP (HDR supported)"), ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.EspOutline end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspOutline = v return true end },
            { Key = "ModMenu_ESPOutline_Color", UI = AliasMap.Slider, Text = T("   Warna Outline (1:Merah 2:Pistol 3:Lam 4:Kuning 5:Ungu 6:Putih)", "   Color (1:Red 2:Grn 3:Blu 4:Ylw 5:Pur 6:Wht)"), ExpandHandle = "ModMenu_ESPOutline_Ex", MinValue = 1, MaxValue = 6, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.OutlineColor or 4 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.OutlineColor = v return true end },
            { Key = "ModMenu_ESPOutline_Thickness", UI = AliasMap.Slider, Text = T("   Nilai Ketebalan Outline", "   Outline Thickness"), ExpandHandle = "ModMenu_ESPOutline_Ex", MinValue = 1, MaxValue = 20, min = 1, max = 20, GetFunc = function() return _G.ZEXYGODXConfig.OutlineThickness end, SetFunc = function(c,v) _G.ZEXYGODXConfig.OutlineThickness = v return true end }
        }

        local StackAimbot = {
    

    { Key = "ModMenu_Magic_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Magic Bullet (GAUSAH PAKE PELER BIAR GA DI BAN)", "▶ Magic Bullet (High Ban Risk)"), ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.CustomMagicBullet end, SetFunc = function(c,v) _G.ZEXYGODXConfig.CustomMagicBullet = v return true end },
    { Key = "ModMenu_Magic_Head", UI = AliasMap.Slider, Text = T("  MB HEAD", "Head Damage"), ExpandHandle = "ModMenu_Magic_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return math.floor(((_G.ZEXYGODXState.CustomTextData.MagicHead or 1.0) / 5.0) * 100 + 0.5) end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.MagicHead = (v / 100.0) * 5.0 return true end },
    { Key = "ModMenu_Magic_Body", UI = AliasMap.Slider, Text = T("MB DADA", "Body Damage"), ExpandHandle = "ModMenu_Magic_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return math.floor(((_G.ZEXYGODXState.CustomTextData.MagicBody or 1.0) / 5.0) * 100 + 0.5) end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.MagicBody = (v / 100.0) * 5.0 return true end },
    { Key = "ModMenu_Magic_Legs", UI = AliasMap.Slider, Text = T("MB PAHA", "Legs Damage"), ExpandHandle = "ModMenu_Magic_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return math.floor(((_G.ZEXYGODXState.CustomTextData.MagicLegs or 1.0) / 5.0) * 100 + 0.5) end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.MagicLegs = (v / 100.0) * 5.0 return true end },
    { Key = "ModMenu_HRecoil_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Kurangi Recoil Ngang (Pasang aksesori aksesori senjata untuk load)", "▶ Less Horizontal Recoil (Equip the accessory to activate it.)"), ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.CustomHRecoil end, SetFunc = function(c,v) _G.ZEXYGODXConfig.CustomHRecoil = v return true end },
    { Key = "ModMenu_HRecoil_Val", UI = AliasMap.Slider, Text = T("   Hanya Jumlah Recoil Ngang (Sebaiknya Geser Ke 0 Untuk Kurangi Nilai Recoil Maksimal Maksimal)", "   Horizontal Recoil Value (Set It To 0 To Minimize Recoil)"), ExpandHandle = "ModMenu_HRecoil_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return math.floor((((_G.ZEXYGODXState.CustomTextData.HRecoil or 0.25) - 0.25) / 4.7) * 100 + 0.5) end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.HRecoil = 0.25 + (v / 100.0) * 4.7 return true end },

    { Key = "ModMenu_VRecoil_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶  Recoil Vertikal (Pasang aksesori aksesori senjata untuk load)", "▶ Less Vertical Recoil (Equip the accessory to activate it.)"), ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.CustomVRecoil end, SetFunc = function(c,v) _G.ZEXYGODXConfig.CustomVRecoil = v return true end },
    { Key = "ModMenu_VRecoil_Val", UI = AliasMap.Slider, Text = T("   Recoil Vertikal (Sebaiknya Geser Ke 0 Untuk Kurangi Nilai Recoil Maksimal Maksimal)", "   Vertical Recoil Value (Set It To 0 To Minimize Recoil)"), ExpandHandle = "ModMenu_VRecoil_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return math.floor((((_G.ZEXYGODXState.CustomTextData.VRecoil or 0.25) - 0.25) / 4.7) * 100 + 0.5) end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.VRecoil = 0.25 + (v / 100.0) * 4.7 return true end },

    
    { Key = "ModMenu_Accuracy", UI = AliasMap.Switcher, Text = T("NO Spread bullet", "No Spread Bullet"), GetFunc = function() return _G.ZEXYGODXConfig.Accuracy end, SetFunc = function(c,v) _G.ZEXYGODXConfig.Accuracy = v return true end },
    { Key = "ModMenu_Crosshair", UI = AliasMap.Switcher, Text = T("Crosshair", "Small Crosshair"), GetFunc = function() return _G.ZEXYGODXConfig.Crosshair end, SetFunc = function(c,v) _G.ZEXYGODXConfig.Crosshair = v return true end }
    }

       local StackAimbotV2 = {
            { Key = "ModMenu_AT_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Aktifkan Aimjembut custum", "▶ Enable Custom Aimjembut"), ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.AimTouchEnable end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchEnable = v return true end },
            { Key = "ModMenu_FovCircle_Main", UI = AliasMap.Switcher, Text = T("▶ TAMPILKAN TAMPILAN LOOP FOV AIMBOT TREN LAYAR KONFIGURASI", "▶ SHOW AIMBOT FOV CIRCLE"), GetFunc = function() return _G.ZEXYGODXConfig.EspFovCircle end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspFovCircle = v return true end },
            
            -- HIPFIRE (CROSSHAIR PUTIH)
            { Key = "ModMenu_AT_Hip_Ex", UI = AliasMap.TitleSwitcher, Text = T("   ▶ Aimbot Crosshair Putih", "   ▶ Hipfire Aimbot"), ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.AimTouchHipfire end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchHipfire = v return true end },
            { Key = "ModMenu_AT_Hip_IgKnock", UI = AliasMap.Switcher, Text = T("      Abaikan Qua Musuh Knock", "      Ignore Knocked"), ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.ZEXYGODXConfig.AimTouchHipIgKnock end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchHipIgKnock = v return true end },
            { Key = "ModMenu_AT_Hip_IgBot", UI = AliasMap.Switcher, Text = T("      Abaikan  Bot", "      Ignore Bots"), ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.ZEXYGODXConfig.AimTouchHipIgBot end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchHipIgBot = v return true end },
            { Key = "ModMenu_AT_Hip_Vis", UI = AliasMap.Switcher, Text = T("      Check Dinding (VisCheck)", "      Visibility Check"), ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.ZEXYGODXConfig.AimTouchHipVisCheck end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchHipVisCheck = v return true end },
            { Key = "ModMenu_AT_Hip_Prio", UI = AliasMap.Slider, Text = T("      Prioritaskan Prioritas (1:Crosshair 2:Dekat 3:HP)", "      Priority (1:Crosshair 2:Distance 3:HP)"), ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchHipPrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.ZEXYGODXState.CustomTextData.AimTouchHipPrio = val return true end },
            { Key = "ModMenu_AT_Hip_Bone", UI = AliasMap.Slider, Text = T("      Posisi Posisi (1:Kepala 2:Dada 3:Perut 4:Pinggul)", "      Bone (1:Head 2:Chest 3:Stomach 4:Pelvis)"), ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchHipBone or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.ZEXYGODXState.CustomTextData.AimTouchHipBone = val return true end },
            { Key = "ModMenu_AT_Hip_Cond", UI = AliasMap.Slider, Text = T("      Kondisi Aksesori (1:Tembak baru Aim, 2:Selalu Aim)", "      Trigger (1:On Fire, 2:Always)"), ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchHipCond or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.ZEXYGODXState.CustomTextData.AimTouchHipCond = val return true end },
            { Key = "ModMenu_AT_Hip_Spd", UI = AliasMap.Slider, Text = T("      Nilai Halus / Kecepatan Nilai (1-100)", "      Smoothness / Speed (1-100)"), ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchHipSpeed or 50 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchHipSpeed = v return true end },
            { Key = "ModMenu_AT_Hip_Dist", UI = AliasMap.Slider, Text = T("      Jarak Jarak (1-500m)", "      Distance Limit (1-500m)"), ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.ZEXYGODXState.CustomTextData.AimTouchHipDist or 250) / 5) end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchHipDist = v * 5 return true end },
            { Key = "ModMenu_AT_Hip_FOV", UI = AliasMap.Slider, Text = T("      Lingkaran FOV (1-100)", "      FOV Radius (1-100)"), ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchHipFOV or 30 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchHipFOV = v return true end },
            { Key = "ModMenu_AT_Hip_FOVColor", UI = AliasMap.Slider, Text = T("      Warna Lingkaran FOV Crosshair Putih (1-7)", "      Circle Color (1-7)"), ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchHipFOVColor or 7 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchHipFOVColor = v return true end },

            -- AIMBOT SHOTGUN
            { Key = "ModMenu_AT_SG_Ex", UI = AliasMap.TitleSwitcher, Text = T("   ▶ Aimbot Shotgun", "   ▶ Shotgun Aimbot"), ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.AimTouchSG end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchSG = v return true end },
            { Key = "ModMenu_AT_SG_AutoFire", UI = AliasMap.Switcher, Text = T("      Otomatis Aksi Tembak", "      Auto Fire"), ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.ZEXYGODXConfig.AimTouchSGAutoFire end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchSGAutoFire = v return true end },
            { Key = "ModMenu_AT_SG_IgKnock", UI = AliasMap.Switcher, Text = T("      Abaikan Qua Musuh Knock", "      Ignore Knocked"), ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.ZEXYGODXConfig.AimTouchSGIgKnock end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchSGIgKnock = v return true end },
            { Key = "ModMenu_AT_SG_IgBot", UI = AliasMap.Switcher, Text = T("      Abaikan Qua Bot", "      Ignore Bots"), ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.ZEXYGODXConfig.AimTouchSGIgBot end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchSGIgBot = v return true end },
            { Key = "ModMenu_AT_SG_Vis", UI = AliasMap.Switcher, Text = T("      Check Dinding (VisCheck)", "      Visibility Check"), ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.ZEXYGODXConfig.AimTouchSGVisCheck end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchSGVisCheck = v return true end },
            { Key = "ModMenu_AT_SG_Prio", UI = AliasMap.Slider, Text = T("      Prioritaskan Prioritas (1:Crosshair 2:Dekat 3:HP)", "      Priority (1:Crosshair 2:Distance 3:HP)"), ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchSGPrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.ZEXYGODXState.CustomTextData.AimTouchSGPrio = val return true end },
            { Key = "ModMenu_AT_SG_Bone", UI = AliasMap.Slider, Text = T("      Posisi Posisi (1:Kepala 2:Dada 3:Perut 4:Pinggul)", "      Bone (1:Head 2:Chest 3:Stomach 4:Pelvis)"), ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchSGBone or 2 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.ZEXYGODXState.CustomTextData.AimTouchSGBone = val return true end },
            { Key = "ModMenu_AT_SG_Cond", UI = AliasMap.Slider, Text = T("      Kondisi Aksesori (1:Tembak baru Aim, 2:Selalu Aim)", "      Trigger (1:On Fire, 2:Always)"), ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchSGCond or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.ZEXYGODXState.CustomTextData.AimTouchSGCond = val return true end },
            { Key = "ModMenu_AT_SG_Spd", UI = AliasMap.Slider, Text = T("      Nilai Halus / Kecepatan Nilai (1-100)", "      Smoothness / Speed (1-100)"), ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchSGSpeed or 80 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchSGSpeed = v return true end },
            { Key = "ModMenu_AT_SG_Dist", UI = AliasMap.Slider, Text = T("      Jarak Jarak (1-100m)", "      Distance Limit (1-100m)"), ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchSGDist or 30 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchSGDist = v return true end },
            { Key = "ModMenu_AT_SG_FOV", UI = AliasMap.Slider, Text = T("      Lingkaran FOV (1-100)", "      FOV Radius (1-100)"), ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchSGFOV or 40 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchSGFOV = v return true end },
            { Key = "ModMenu_AT_SG_FOVColor", UI = AliasMap.Slider, Text = T("      Warna Lingkaran FOV Shotgun (1-7)", "      Circle Color (1-7)"), ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchSGFOVColor or 1 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchSGFOVColor = v return true end },
            
            -- SCOPE ALL (SENJATA BIASA KHI BUKA SCOPE)
            { Key = "ModMenu_AT_ScopeAll_Ex", UI = AliasMap.TitleSwitcher, Text = T("   ▶ Aimbot Buka Scope", "   ▶ Scope Aimbot"), ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.AimTouchScopeAll end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchScopeAll = v return true end },
            { Key = "ModMenu_AT_ScopeAll_IgKnock", UI = AliasMap.Switcher, Text = T("      Abaikan Qua Musuh Knock", "      Ignore Knocked"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.ZEXYGODXConfig.AimTouchScopeIgKnock end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchScopeIgKnock = v return true end },
            { Key = "ModMenu_AT_ScopeAll_IgBot", UI = AliasMap.Switcher, Text = T("      Abaikan Qua Bot", "      Ignore Bots"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.ZEXYGODXConfig.AimTouchScopeIgBot end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchScopeIgBot = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Vis", UI = AliasMap.Switcher, Text = T("      Check Dinding (VisCheck)", "      Visibility Check"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.ZEXYGODXConfig.AimTouchScopeVisCheck end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchScopeVisCheck = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Prio", UI = AliasMap.Slider, Text = T("      Prioritaskan Prioritas (1:Crosshair 2:Dekat 3:HP)", "      Priority (1:Crosshair 2:Distance 3:HP)"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchScopePrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.ZEXYGODXState.CustomTextData.AimTouchScopePrio = val return true end },
            { Key = "ModMenu_AT_ScopeAll_Bone", UI = AliasMap.Slider, Text = T("      Posisi Posisi (1:Kepala 2:Dada 3:Perut 4:Pinggul)", "      Bone (1:Head 2:Chest 3:Stomach 4:Pelvis)"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchScopeBone or 2 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.ZEXYGODXState.CustomTextData.AimTouchScopeBone = val return true end },
            { Key = "ModMenu_AT_ScopeAll_Cond", UI = AliasMap.Slider, Text = T("      Kondisi Aksesori (1:Tembak baru Aim, 2:Selalu Aim)", "      Trigger (1:On Fire, 2:Always)"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchScopeCond or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.ZEXYGODXState.CustomTextData.AimTouchScopeCond = val return true end },
            { Key = "ModMenu_AT_ScopeAll_Spd", UI = AliasMap.Slider, Text = T("      Nilai Halus / Kecepatan Nilai (1-100)", "      Smoothness / Speed (1-100)"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchScopeSpeed or 40 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchScopeSpeed = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Dist", UI = AliasMap.Slider, Text = T("      Jarak Jarak (1-500m)", "      Distance Limit (1-500m)"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.ZEXYGODXState.CustomTextData.AimTouchScopeDist or 300) / 5) end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchScopeDist = v * 5 return true end },
            { Key = "ModMenu_AT_ScopeAll_Pred", UI = AliasMap.Slider, Text = T("      Prediksi Prediksi Arah Gerak", "      Prediction Value"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchScopePred or 0 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchScopePred = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Recoil", UI = AliasMap.Slider, Text = T("      Kompensasi Recoil Otomatis Aksi", "      Auto Recoil Comp."), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 0, MaxValue = 50, min = 0, max = 50, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchScopeRecoil or 0 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchScopeRecoil = v return true end },
            { Key = "ModMenu_AT_ScopeAll_FOV", UI = AliasMap.Slider, Text = T("      Lingkaran FOV (1-100)", "      FOV Radius (1-100)"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchScopeFOV or 20 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchScopeFOV = v return true end },
            { Key = "ModMenu_AT_ScopeAll_FOVColor", UI = AliasMap.Slider, Text = T("      Warna Lingkaran FOV Scope (1-7)", "      Circle Color (1-7)"), ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchScopeFOVColor or 6 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchScopeFOVColor = v return true end },

            -- SCOPE SNIPER (SENJATA BIDIK/SNIPER)
            { Key = "ModMenu_AT_Sniper_Ex", UI = AliasMap.TitleSwitcher, Text = T("   ▶ Aimbot Buka Scope (Senjata Bidik/Sniper)", "   ▶ Sniper Aimbot"), ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.AimTouchScopeSniper end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchScopeSniper = v return true end },
            { Key = "ModMenu_AT_Sniper_IgKnock", UI = AliasMap.Switcher, Text = T("      Abaikan Qua Musuh Knock", "      Ignore Knocked"), ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.ZEXYGODXConfig.AimTouchSniperIgKnock end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchSniperIgKnock = v return true end },
            { Key = "ModMenu_AT_Sniper_IgBot", UI = AliasMap.Switcher, Text = T("      Abaikan Qua Bot", "      Ignore Bots"), ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.ZEXYGODXConfig.AimTouchSniperIgBot end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchSniperIgBot = v return true end },
            { Key = "ModMenu_AT_Sniper_Vis", UI = AliasMap.Switcher, Text = T("      Check Dinding (VisCheck)", "      Visibility Check"), ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.ZEXYGODXConfig.AimTouchSniperVisCheck end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchSniperVisCheck = v return true end },
            { Key = "ModMenu_AT_Sniper_Prio", UI = AliasMap.Slider, Text = T("      Prioritaskan Prioritas (1:Crosshair 2:Dekat 3:HP)", "      Priority (1:Crosshair 2:Distance 3:HP)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchSniperPrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.ZEXYGODXState.CustomTextData.AimTouchSniperPrio = val return true end },
            { Key = "ModMenu_AT_Sniper_Bone", UI = AliasMap.Slider, Text = T("      Posisi Posisi (1:Kepala 2:Dada 3:Perut 4:Pinggul)", "      Bone (1:Head 2:Chest 3:Stomach 4:Pelvis)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchSniperBone or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.ZEXYGODXState.CustomTextData.AimTouchSniperBone = val return true end },
            { Key = "ModMenu_AT_Sniper_Cond", UI = AliasMap.Slider, Text = T("      Kondisi Aksesori (1:Tembak baru Aim, 2:Selalu Aim)", "      Trigger (1:On Fire, 2:Always)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchSniperCond or 2 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.ZEXYGODXState.CustomTextData.AimTouchSniperCond = val return true end },
            { Key = "ModMenu_AT_Sniper_Spd", UI = AliasMap.Slider, Text = T("      Nilai Halus / Kecepatan Nilai (1-100)", "      Smoothness / Speed (1-100)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchSniperSpeed or 30 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchSniperSpeed = v return true end },
            { Key = "ModMenu_AT_Sniper_Dist", UI = AliasMap.Slider, Text = T("      Jarak Jarak (1-500m)", "      Distance Limit (1-500m)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.ZEXYGODXState.CustomTextData.AimTouchSniperDist or 400) / 5) end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchSniperDist = v * 5 return true end },
            { Key = "ModMenu_AT_Sniper_Pred", UI = AliasMap.Slider, Text = T("      Prediksi Prediksi Arah Gerak (0-100)", "      Prediction Value (0-100)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchSniperPred or 0 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchSniperPred = v return true end },
            { Key = "ModMenu_AT_Sniper_FOV", UI = AliasMap.Slider, Text = T("      Lingkaran FOV (1-100)", "      FOV Radius (1-100)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchSniperFOV or 20 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchSniperFOV = v return true end },
            { Key = "ModMenu_AT_Sniper_FOVColor", UI = AliasMap.Slider, Text = T("      Warna Lingkaran FOV Bidik/Sniper (1-7)", "      Circle Color (1-7)"), ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchSniperFOVColor or 4 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchSniperFOVColor = v return true end },

            -- AIMBOT SENJATA MORTIR (MORTAR)
            { Key = "ModMenu_AT_Mortar_Ex", UI = AliasMap.TitleSwitcher, Text = T("   ▶ Aimbot Senjata Mortir (Mortar)", "   ▶ Mortar Aimbot"), ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.AimTouchMortar end, SetFunc = function(c,v) _G.ZEXYGODXConfig.AimTouchMortar = v return true end },
            { Key = "ModMenu_AT_Mortar_Pred", UI = AliasMap.Slider, Text = T("      Prediksi Prediksi Arah Gerak (0-100)", "      Prediction Value (0-100)"), ExpandHandle = "ModMenu_AT_Mortar_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchMortarPred or 0 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchMortarPred = v return true end },
            { Key = "ModMenu_AT_Mortar_FOV", UI = AliasMap.Slider, Text = T("      Lingkaran FOV (1-360)", "      FOV Radius (1-360)"), ExpandHandle = "ModMenu_AT_Mortar_Ex", MinValue = 1, MaxValue = 360, min = 1, max = 360, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchMortarFOV or 360 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchMortarFOV = v return true end },
            { Key = "ModMenu_AT_Mortar_FOVColor", UI = AliasMap.Slider, Text = T("      Warna Lingkaran FOV Mortir (1-7)", "      Circle Color (1-7)"), ExpandHandle = "ModMenu_AT_Mortar_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.AimTouchMortarFOVColor or 5 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.AimTouchMortarFOVColor = v return true end }
        }

        local StackSkin = {
            
            { Key = "ModMenu_ModEmote", UI = AliasMap.Switcher, Text = T("Buka Kunci Full Aksi Aksi VIP (Emotes)", "Unlock All VIP Emotes"), GetFunc = function() return _G.ZEXYGODXConfig.ModEmote end, SetFunc = function(c,v) _G.ZEXYGODXConfig.ModEmote = v return true end },
            { Key = "ModMenu_ModSkin", UI = AliasMap.Switcher, Text = T("Sistem Sistem Mod Skin VIP (Buka tas barang pilih)", "VIP Mod Skin System (Open inventory)"), GetFunc = function() return _G.ZEXYGODXConfig.ModSkin end, SetFunc = function(c,v) _G.ZEXYGODXConfig.ModSkin = v return true end },
    { Key = "ModMenu_SkinDeadBox", UI = AliasMap.Switcher, Text = T("Skin Kotak Mayat (Sangat Lag ,Sebaiknya Nonaktifkan)", "Deadbox Skin (Very Lag, Should Off)"), GetFunc = function() return _G.ZEXYGODXConfig.SkinDeadBox end, SetFunc = function(c,v) _G.ZEXYGODXConfig.SkinDeadBox = v return true end },
    { Key = "ModMenu_SkinAttachment", UI = AliasMap.Switcher, Text = T("Skin Aksesori Aksesori Senjata (Sebaiknya Nonaktifkan Cho Kurangi Lag)", "Weapon Attachment Skin (Should Turn Off To Lag Fix"), GetFunc = function() return _G.ZEXYGODXConfig.SkinAttachment end, SetFunc = function(c,v) _G.ZEXYGODXConfig.SkinAttachment = v return true end },
    { Key = "ModMenu_KillMessage", UI = AliasMap.Switcher, Text = T("Info Peringatan Eliminasi VIP (Sebaiknya Nonaktifkan Cho Kurangi Lag)", "VIP Kill Messenger (Should Turn Off To Lag Fix)"), GetFunc = function() return _G.ZEXYGODXConfig.KillMessage end, SetFunc = function(c,v) _G.ZEXYGODXConfig.KillMessage = v return true end },
    { Key = "ModMenu_KillCountUI", UI = AliasMap.Switcher, Text = T("Paket Hitung Kill (Sebaiknya Nonaktifkan Cho Kurangi Lag)", "Kill Counter UI (Should Turn Off To Lag Fix"), GetFunc = function() return _G.ZEXYGODXConfig.KillCountUI end, SetFunc = function(c,v) _G.ZEXYGODXConfig.KillCountUI = v return true end },
            { Key = "ModMenu_SkinOpenLink", UI = AliasMap.Switcher, Text = T("Arah Panduan Mod Skin Helm/Balo (Link)", "Mod Skin Guide (Link)"), GetFunc = function() return _G.ZEXYGODXConfig.SkinOpenLink end, SetFunc = function(c,v) _G.ZEXYGODXConfig.SkinOpenLink = v; if v == true then pcall(function() local Web = require("client.slua.logic.url.logic_webview_sdk"); if Web and Web.OpenURL then Web:OpenURL("https://t.me/venusmod2/3082") end end) end return true end },
        }

        local StackCombat = {
            
            
            { Key = "ModMenu_Ipad_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Ipad View", "▶ Ipad View"), ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.IpadView end, SetFunc = function(c,v) _G.ZEXYGODXConfig.IpadView = v return true end },
            { Key = "ModMenu_Ipad_FOV", UI = AliasMap.Slider, Text = T("   Sudut Pandangan FOV", "   FOV Value"), ExpandHandle = "ModMenu_Ipad_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return (_G.ZEXYGODXState.CustomTextData.IpadViewFOV or 120) - 90 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.IpadViewFOV = 90 + v return true end },

            { Key = "ModMenu_IpadVeh_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Ipad View Mengemudi Xe", "▶ Ipad View Vehicle"), ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.IpadViewVehicle end, SetFunc = function(c,v) _G.ZEXYGODXConfig.IpadViewVehicle = v return true end },
            { Key = "ModMenu_IpadVeh_FOV", UI = AliasMap.Slider, Text = T("   FOV Khi Mengemudi Xe", "   Vehicle FOV Value"), ExpandHandle = "ModMenu_IpadVeh_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return (_G.ZEXYGODXState.CustomTextData.IpadViewVehicleFOV or 120) - 90 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.IpadViewVehicleFOV = 90 + v return true end },

            { Key = "ModMenu_IpadScope_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Ipad View Khi Buka Scope", "▶ Ipad View Scope"), ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.IpadViewScope end, SetFunc = function(c,v) _G.ZEXYGODXConfig.IpadViewScope = v return true end },
            { Key = "ModMenu_IpadScope_FOV", UI = AliasMap.Slider, Text = T("   FOV Khi Buka Scope (30-120)", "   Scope FOV (30-120)"), ExpandHandle = "ModMenu_IpadScope_Ex", MinValue = 30, MaxValue = 120, min = 30, max = 120, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.IpadViewScopeFOV or 60 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.IpadViewScopeFOV = v return true end },

            { Key = "ModMenu_165FPS", UI = AliasMap.Switcher, Text = T("Buka Kunci 165 FPS", "Unlock 165 FPS"), GetFunc = function() return _G.ZEXYGODXConfig.UnlockFPS end, SetFunc = function(c,v) _G.ZEXYGODXConfig.UnlockFPS = v; if v then _G.ZEXYGODXState.GraphicsUnlocked = false end return true end },
            
            { Key = "ModMenu_WallXuyenTuong", UI = AliasMap.Switcher, Text = T("Wall Tembus Dinding V1 (Hanya lihat tembus)", "Wallhack V1 (See through)"), GetFunc = function() return _G.ZEXYGODXConfig.WallXuyenTuong end, SetFunc = function(c,v) _G.ZEXYGODXConfig.WallXuyenTuong = v return true end },
            { Key = "ModMenu_ColorBodyV2", UI = AliasMap.Switcher, Text = T("Warnai Warna Musuh V2 (Chams Dasar Dasar)", "Chams V2 (Basic Color)"), GetFunc = function() return _G.ZEXYGODXConfig.ColorBodyV2 end, SetFunc = function(c,v) _G.ZEXYGODXConfig.ColorBodyV2 = v return true end },
            { Key = "ModMenu_ColorBodyNew", UI = AliasMap.Switcher, Text = T("WALL + WARNA V3 (Xanh Khi Terlihat/Merah Khi Tertutup)", "WALL+WARNA V3 (Red/Green)"), GetFunc = function() return _G.ZEXYGODXConfig.ColorBodyNew end, SetFunc = function(c,v) _G.ZEXYGODXConfig.ColorBodyNew = v return true end },
            
            
            { Key = "ModMenu_WallVehicle", UI = AliasMap.Switcher, Text = T("Wall Kendaraan Kendaraan", "Vehicle Wallhack"), GetFunc = function() return _G.ZEXYGODXConfig.WallVehicle end, SetFunc = function(c,v) _G.ZEXYGODXConfig.WallVehicle = v return true end },

            { Key = "ModMenu_WhiteBody", UI = AliasMap.Switcher, Text = T("Pemain Putih", "White Body"), GetFunc = function() return _G.ZEXYGODXConfig.WhiteBody end, SetFunc = function(c,v) _G.ZEXYGODXConfig.WhiteBody = v return true end },
            { Key = "ModMenu_BlackSky", UI = AliasMap.Switcher, Text = T("Langit Maksimal", "Black Sky"), GetFunc = function() return _G.ZEXYGODXConfig.BlackSky end, SetFunc = function(c,v) _G.ZEXYGODXConfig.BlackSky = v return true end },
            { Key = "ModMenu_RemoveFog", UI = AliasMap.Switcher, Text = T("Hapus Kabut Kabut", "Remove Fog"), GetFunc = function() return _G.ZEXYGODXConfig.RemoveFog end, SetFunc = function(c,v) _G.ZEXYGODXConfig.RemoveFog = v return true end },
            { Key = "ModMenu_RemoveGrass", UI = AliasMap.Switcher, Text = T("Hapus Rumput", "Remove Grass"), GetFunc = function() return _G.ZEXYGODXConfig.RemoveGrass end, SetFunc = function(c,v) _G.ZEXYGODXConfig.RemoveGrass = v return true end },
            { Key = "ModMenu_RemoveTrees", UI = AliasMap.Switcher, Text = T("Hapus Pohon", "Remove Trees"), GetFunc = function() return _G.ZEXYGODXConfig.RemoveTrees end, SetFunc = function(c,v) _G.ZEXYGODXConfig.RemoveTrees = v return true end },
            

            { Key = "ModMenu_WeaponGlow_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ Glow Outline Senjata (Terang terang HDR)", "▶ Weapon Glow (HDR)"), ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.WeaponGlow end, SetFunc = function(c,v) _G.ZEXYGODXConfig.WeaponGlow = v return true end },
            { Key = "ModMenu_WeaponGlowColor", UI = AliasMap.Slider, Text = T("   Warna Senjata (1:Merah 2:Pistol 3:Lam 4:Kuning 5:Rainbow)", "   Color (1:Red 2:Grn 3:Blu 4:Ylw 5:Rnb)"), ExpandHandle = "ModMenu_WeaponGlow_Ex", MinValue = 1, MaxValue = 5, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.WeaponGlowColor or 5 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.WeaponGlowColor = v return true end },
            { Key = "ModMenu_WeaponGlowThick", UI = AliasMap.Slider, Text = T("   Nilai Ketebalan Outline Senjata", "   Glow Thickness"), ExpandHandle = "ModMenu_WeaponGlow_Ex", MinValue = 1, MaxValue = 15, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.WeaponGlowThickness or 3 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.WeaponGlowThickness = v return true end }
        }

        local StackESPV2 = {
            { Key = "ModMenu_ESP9_Ex", UI = AliasMap.TitleSwitcher, Text = T("▶ ESP VIP V2", "▶ ESP VIP V2"), ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.EspLoai9 end, SetFunc = function(c,v) _G.ZEXYGODXConfig.EspLoai9 = v return true end },
            { Key = "ModMenu_ESP9_Count", UI = AliasMap.Switcher, Text = T("   Tampilkan Tabel Hitung Pemain", "   Show Player Count"), ExpandHandle = "ModMenu_ESP9_Ex", GetFunc = function() return _G.ZEXYGODXConfig.Esp9_Count end, SetFunc = function(c,v) _G.ZEXYGODXConfig.Esp9_Count = v return true end },
            { Key = "ModMenu_ESP9_Name", UI = AliasMap.Switcher, Text = T("   Tampilkan Nama Pemain Main", "   Show Player Name"), ExpandHandle = "ModMenu_ESP9_Ex", GetFunc = function() return _G.ZEXYGODXConfig.Esp9_Name end, SetFunc = function(c,v) _G.ZEXYGODXConfig.Esp9_Name = v return true end },
            { Key = "ModMenu_ESP9_Dist", UI = AliasMap.Switcher, Text = T("   Tampilkan Jarak Jarak", "   Show Distance"), ExpandHandle = "ModMenu_ESP9_Ex", GetFunc = function() return _G.ZEXYGODXConfig.Esp9_Distance end, SetFunc = function(c,v) _G.ZEXYGODXConfig.Esp9_Distance = v return true end },
            { Key = "ModMenu_ESP9_HP", UI = AliasMap.Switcher, Text = T("   Tampilkan Thanh HP", "   Show Health Bar"), ExpandHandle = "ModMenu_ESP9_Ex", GetFunc = function() return _G.ZEXYGODXConfig.Esp9_HP end, SetFunc = function(c,v) _G.ZEXYGODXConfig.Esp9_HP = v return true end },
            { Key = "ModMenu_ESP9_Team", UI = AliasMap.Switcher, Text = T("   Tampilkan Khung Warna Team", "   Show Team Color Box"), ExpandHandle = "ModMenu_ESP9_Ex", GetFunc = function() return _G.ZEXYGODXConfig.Esp9_Team end, SetFunc = function(c,v) _G.ZEXYGODXConfig.Esp9_Team = v return true end },
            { Key = "ModMenu_ESP9_Weapon", UI = AliasMap.Switcher, Text = T("   Tampilkan Icon Senjata", "   Show Weapon Icon"), ExpandHandle = "ModMenu_ESP9_Ex", GetFunc = function() return _G.ZEXYGODXConfig.Esp9_Weapon end, SetFunc = function(c,v) _G.ZEXYGODXConfig.Esp9_Weapon = v return true end },
            
            { Key = "ModMenu_ESP9_Line", UI = AliasMap.TitleSwitcher, Text = T("   ▶ Tampilkan Garis Penghubung (Snapline)", "   ▶ Show Snapline"), ExpandHandle = "ModMenu_ESP9_Ex", ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.Esp9_Line end, SetFunc = function(c,v) _G.ZEXYGODXConfig.Esp9_Line = v return true end },
            { Key = "ModMenu_ESP9_Line_Thick", UI = AliasMap.Slider, Text = T("      Nilai Ketebalan Garis Penghubung", "      Line Thickness"), ExpandHandle = "ModMenu_ESP9_Line", MinValue = 1, MaxValue = 10, min = 1, max = 10, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.Esp9_LineThick or 1 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.Esp9_LineThick = v return true end },
            { Key = "ModMenu_ESP9_Line_VisColor", UI = AliasMap.Slider, Text = T("      Warna Terlihat Tampilan (1-30 Tabel Warna Kustom Pilihan)", "      Visible Color (1-30)"), ExpandHandle = "ModMenu_ESP9_Line", MinValue = 1, MaxValue = 30, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.Esp9_LineVisColor or 2 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.Esp9_LineVisColor = v return true end },
            { Key = "ModMenu_ESP9_Line_HidColor", UI = AliasMap.Slider, Text = T("      Warna Sau Dinding (1-30 Tabel Warna Kustom Pilihan)", "      Hidden Color (1-30)"), ExpandHandle = "ModMenu_ESP9_Line", MinValue = 1, MaxValue = 30, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.Esp9_LineHidColor or 1 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.Esp9_LineHidColor = v return true end },

            { Key = "ModMenu_ESP9_Skeleton", UI = AliasMap.TitleSwitcher, Text = T("   ▶ Tampilkan Khung Tulang (Bisa Bentuk Menyebabkan Lag Dan Mudah Crash)", "   ▶ Show Skeleton (Can cause lag and crashes)"), ExpandHandle = "ModMenu_ESP9_Ex", ExpandIndex = 0, GetFunc = function() return _G.ZEXYGODXConfig.Esp9_Skeleton end, SetFunc = function(c,v) _G.ZEXYGODXConfig.Esp9_Skeleton = v return true end },
            { Key = "ModMenu_ESP9_Skel_Thick", UI = AliasMap.Slider, Text = T("      Nilai Ketebalan Khung Tulang", "      Skeleton Thickness"), ExpandHandle = "ModMenu_ESP9_Skeleton", MinValue = 1, MaxValue = 10, min = 1, max = 10, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.Esp9_SkelThick or 1 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.Esp9_SkelThick = v return true end },
            { Key = "ModMenu_ESP9_Skel_VisColor", UI = AliasMap.Slider, Text = T("      Warna Terlihat Tampilan (1-30 Tabel Warna Kustom Pilihan)", "      Visible Color (1-30)"), ExpandHandle = "ModMenu_ESP9_Skeleton", MinValue = 1, MaxValue = 30, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.Esp9_SkelVisColor or 2 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.Esp9_SkelVisColor = v return true end },
            { Key = "ModMenu_ESP9_Skel_HidColor", UI = AliasMap.Slider, Text = T("      Warna Sau Dinding (1-30 Tabel Warna Kustom Pilihan)", "      Hidden Color (1-30)"), ExpandHandle = "ModMenu_ESP9_Skeleton", MinValue = 1, MaxValue = 30, GetFunc = function() return _G.ZEXYGODXState.CustomTextData.Esp9_SkelHidColor or 1 end, SetFunc = function(c,v) _G.ZEXYGODXState.CustomTextData.Esp9_SkelHidColor = v return true end }
        }

        SettingPageDefine.ModMenu = {
            Key = "ModMenu",
            Text = 999000, 
            UIKey = "Setting_Page_Privacy", 
            Category = {
                { Key = "Cat_ESP", Text = 999001, Stack = StackESP },
                
                { Key = "Cat_Aimbot", Text = 999002, Stack = StackAimbot },
                { Key = "Cat_AimbotV2", Text = 999003, Stack = StackAimbotV2 },
                { Key = "Cat_Combat", Text = 999004, Stack = StackCombat }
                
            }
        }
        
        table.insert(SettingCatalog, 1, SettingPageDefine.ModMenu)
    end

    local UIManager = _G.UIManager
    if UIManager and not UIManager._IsModMenuHooked then
        local old_ShowUI = UIManager.ShowUI
        UIManager.ShowUI = function(config, ...)
            local args = {...}
            local n = select('#', ...) 
            
            if config and config.keyName then
                local lowerKeyName = string.lower(config.keyName)
                if string.find(lowerKeyName, "setting_main") and not string.find(lowerKeyName, "custom") then
                    local catalog = args[1]
                    if type(catalog) == "table" and catalog[1] and type(catalog[1]) == "table" and catalog[1].Key then
                        local hasModMenu = false
                        for _, page in ipairs(catalog) do
                            if type(page) == "table" and page.Key == "ModMenu" then
                                hasModMenu = true
                                break
                            end
                        end
                        if not hasModMenu then
                            table.insert(catalog, 1, SettingPageDefine.ModMenu)
                        end
                    end
                end
            end
            local table_unpack = table.unpack or unpack
            return old_ShowUI(config, table_unpack(args, 1, n))
        end
        UIManager._IsModMenuHooked = true
    end
end

local function ShowZEXYGODXVIPMenu() 
    if _G.ZEXYGODXMenuAlreadyShown then return end
    if _G.ZEXYGODXState.MenuStep ~= 0 then return end

    pcall(function()
        local Msg = require("client.slua.logic.common.logic_common_msg_box")
        if not Msg or not Msg.Show then return end

        local function Step_ScamAlert()
            local title = _G.ZEXYGODXLang == "EN" and "SCAM ALERT" or "PERINGATAN PERINGATAN SCAM MOD"
            local content = _G.ZEXYGODXLang == "EN" 
                and "JOIN KE @GODMOD SELAIN ITU SCAM GUE GA PERNAH JUALAN DI WA BUY LANGSUNG KE TELEGRAM" 
                or "AWAS BANYAK YANG SCAM DI WA FUCK POKOKNYA INTINYA LANGSUNG JOIN TELEGRAM @GODMOD REAL OWNER @zexygodx\nBANYAK YANG NGAKU SELER HATI HATI SAYA TIDAK PUNYA RESELER"
            local btn1 = _G.ZEXYGODXLang == "EN" and "JOIN" or "JOIN PLER"
            local btn2 = _G.ZEXYGODXLang == "EN" and "CLOSE" or "TUTUP"

            Msg.Show(1, title, content, function() local Web = require("client.slua.logic.url.logic_webview_sdk"); if Web and Web.OpenURL then Web:OpenURL("https://t.me/venusmod2") end end, function() end, btn1, btn2)
            _G.ZEXYGODXState.MenuStep = 99
            _G.ZEXYGODXMenuAlreadyShown = true
        end

        local function Step_Welcome()
            local title = _G.ZEXYGODXLang == "EN" and "NOTIFICATION DARI GODMOD" or "PEMBERITAHUAN PERINGATAN DARI ADMIN GOD MOD"
            local content = _G.ZEXYGODXLang == "EN" 
                and "MAIN SANTAI AJA SELAYAKNYA PRO PELER JANGAN SANGEAN JADI ORANG KALO SAYANG SAMA AKUN" 
                or "FEEDBACK YA PELER BIAR GUE SEMANGAT UPDATE\nJANGAN AKTIFIN BANYAK FITUR KALO NGEFRAME KALO KENTANG GAUSAH MAKSA DEK"
            local btn1 = _G.ZEXYGODXLang == "EN" and "OPEN GAME MENU" or "BUKA MENU"
            local btn2 = _G.ZEXYGODXLang == "EN" and "CLOSE" or "TUTUP"

            Msg.Show(1, title, content, 
            function() 
                _G.InitModMenuTab()
                if _G.ZEXYGODXLang == "EN" then
                    Notify("VIP MOD MENU ADDED!\nOpen Settings (Gear icon) -> VIP MOD MENU to toggle features.")
                else
                    Notify("SUDAH TAMBAH 'VIP MOD MENU' KE KOMPONEN PENGATURAN PENGATURAN MILIK GAME!/Silakan buka Pengaturan Pengaturan  -> VIP MOD MENU untuk aktifkan/nonaktifkan.")
                end
                Step_ScamAlert()
            end, 
            function() end, btn1, btn2)
        end

        local function Step_SelectLanguage()
            Msg.Show(2, "SELECT LANGUAGE / PILIH BAHASA BAHASA", "Please select your preferred language.\nVui ingin pilih bahasa bahasa anda ingin menggunakan menggunakan.",
            function()
                _G.ZEXYGODXLang = "KONOHA"
                Step_Welcome()
            end,
            function()
                _G.ZEXYGODXLang = "EN"
                Step_Welcome()
            end, "BAHASA KONOHA", "ENGLISH")
        end

        local function Step_LegalNotice()
            local legal_title = "Info Peringatan Dari Admin@zexygodx - Announcement from Admin@zexygodx"
            local legal_content = "X9  FIX LAG DAN CRASH  (X9 FIXES LAG AND CRASHING ON SOME LOW-END DEVICES)\nMAGIC BULLET = RISK BAN X\nGLOBAL = SAFE ✓( SAFE )\nVNG = SAFE ✓( SAFE )\nKOREA = SAFE ✓(SAFE)\nTAIWAN = SAFE ✓( SAFE )"
            local legal_btnOK = "Setuju SEPAKAT SEPENDAPAT (Agree)"
            local legal_btnCancel = "Batal (cancel)"
            local legal_url = "https://t.me/venusmod2" 

            local legal_msg = require("client.slua.logic.common.logic_common_legal_msg")
            if not legal_msg then
                -- Jika game kurang direktori library legal, fallback alih selalu sang menu pilih bahasa bahasa
                Step_SelectLanguage()
                return
            end
            
            legal_msg.ShowOnePopUI({
                tabType = 0,
                title = legal_title,
                content = legal_content,
                tipsText = nil,
                btnOKText = legal_btnOK,
                btnCancelText = legal_btnCancel, 
                acceptFunc = function()
                    -- Tekan Confirm -> Buka menu pilih bahasa bahasa
                    Step_SelectLanguage()
                end,
                refuseFunc = function()
                    -- Tekan Join Channel -> Buka link Telegram -> Buka menu pilih bahasa bahasa
                    local KismetSystemLibrary = import("KismetSystemLibrary")
                    if KismetSystemLibrary then
                        KismetSystemLibrary:LaunchURL(legal_url)
                    end
                    Step_SelectLanguage()
                end
            })
        end

        _G.ZEXYGODXState.MenuStep = 1
        -- Panggil menu Legal Notice awal prioritas thay karena menu pilih Bahasa Bahasa
        Step_LegalNotice() 
    end)
end

-- ========================================== 
-- LOGIC BUKA BUKA KUNCI 165 FPS DAN UI IPAD VIEW 
-- ========================================== 
local function InitializeGraphicsUnlock() 
    if isExpired then return end
    if _G.ZEXYGODXState.GraphicsUnlocked or currentTime > limitTime then return end

    pcall(function()
        local SettingCfg = require("client.logic.setting.setting_config")
        local GraphicSettingDB = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
        if SettingCfg then
            if SettingCfg.TpViewValue then SettingCfg.TpViewValue.max = 160 end
            if SettingCfg.FpViewValue then SettingCfg.FpViewValue.max = 160 end
        end
        if GraphicSettingDB then
            if GraphicSettingDB.TpViewValue then GraphicSettingDB.TpViewValue.max = 160 end
        end
    end)

    pcall(function()
        local logic_setting_graphics = require("client.slua.logic.setting.logic_setting_graphics")
        local GSC_FPS = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS")
        local GSC_FPSFT = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPSFT")
        local GraphicSettingDB = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
        
        local KismetMathLibrary = import("KismetMathLibrary") or _G.KismetMathLibrary
        local FLinearColor = import("LinearColor") or _G.FLinearColor

        if logic_setting_graphics then
            local old_SetFPS = logic_setting_graphics.SetFPS
            function logic_setting_graphics.SetFPS(gameInstance, FPSLevel)
                if old_SetFPS then old_SetFPS(gameInstance, FPSLevel) end
                if FPSLevel == 8 then 
                    gameInstance:ExecuteCMD("t.MaxFPS", "165")
                    gameInstance:ExecuteCMD("r.FrameRateLimit", "165")
                end
            end
        end

        if GSC_FPS and GSC_FPS.__inner_impl then
            local fps_impl = GSC_FPS.__inner_impl
            function fps_impl:GetMaxFPSLevel() return 8, 8 end
            function fps_impl:InitRealSupportFPS()
                local RealSupportFPS = {}
                for i = 1, 8 do RealSupportFPS[i] = {true, true} end
                if GraphicSettingDB then GraphicSettingDB:UpdateUIData(GraphicSettingDB.RealSupportFPS, RealSupportFPS, false) end
                return RealSupportFPS
            end
            function fps_impl:UpdateSelectedFPSState(selectedLevel)
                if not slua.isValid(self.UIRoot) then return end
                for level = 2, 8 do
                    local name = "NodeFps" .. (({[2]=20,[3]=25,[4]=30,[5]=40,[6]=60,[7]=90,[8]=120})[level] or 120)
                    local widget = self.UIRoot[name]
                    if slua.isValid(widget) then
                        widget:SetIsEnabled(true) 
                        pcall(function() widget:SetRenderOpacity(1.0) end)
                        local switcher = self.UIRoot["WidgetSwitcher_" .. level]
                        if slua.isValid(switcher) then 
                            switcher:SetActiveWidgetIndex(level == selectedLevel and 0 or 1) 
                        end
                    end
                end
            end
        end

        if GSC_FPSFT and GSC_FPSFT.__inner_impl then
            local ft_impl = GSC_FPSFT.__inner_impl
            local NMinFPS, NStep = 90, 5
            local function clamp(value, min, max)
                if value < min then return min end
                if max < value then return max end
                return value
            end
            local function lerp(a, b, t) return a + (b - a) * t end
            local function _getColorByPercent(start, finish, percent)
                if not FLinearColor then return nil end
                return FLinearColor(lerp(start.R, finish.R, percent), lerp(start.G, finish.G, percent), lerp(start.B, finish.B, percent), lerp(start.A, finish.A, percent))
            end
            
            ft_impl.ShowOrHide = function(self)
                self:SelfHitTestInvisible()
                if self.InitFPSFTSwitch then self:InitFPSFTSwitch() end
            end

            ft_impl.InitFPSFTSwitch = function(self)
                local FPSFineTuneSwitch = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch)
                if self.UIRoot.Setting_Switch then self.UIRoot.Setting_Switch:SetSwitcherEnable2(FPSFineTuneSwitch, true) end
                if self.UIRoot.CanvasPanel_8 then self:SetWidgetVisible(self.UIRoot.CanvasPanel_8, FPSFineTuneSwitch) end
                if self.UIRoot.WidgetSwitcher_0 then self.UIRoot.WidgetSwitcher_0:SetActiveWidgetIndex(2) end
                if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
            end

            ft_impl.InitFPSFTValue165 = function(self)
                local itemRoot = self.UIRoot
                local FPSFineTuneSwitch = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch)
                local FPSFineTuneNum = 165
                if FPSFineTuneSwitch then
                    FPSFineTuneNum = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneNum) or 165
                    itemRoot.Slider_screen3:SetLocked(false)
                    if FLinearColor then
                        itemRoot.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1.0, 1.0, 1.0, 1.0))
                        itemRoot.Slider_screen3:SetSliderHandleColor(FLinearColor(1.0, 1.0, 1.0, 1.0))
                    end
                else
                    itemRoot.Slider_screen3:SetLocked(true)
                    if FLinearColor then
                        itemRoot.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1.0, 0.625, 0.6, 1))
                        itemRoot.Slider_screen3:SetSliderHandleColor(FLinearColor(1.0, 0.625, 0.6, 1.0))
                    end
                end
                local FPSFineTunePer = (FPSFineTuneNum - NMinFPS) / (165 - NMinFPS)
                
                itemRoot.Veihclescreen3:SetText(tostring(FPSFineTuneNum))
                itemRoot.Slider_screen3:SetValue(FPSFineTunePer)
                itemRoot.ProgressBar_screen3:SetPercent(FPSFineTunePer)
                
                if FLinearColor then
                    local startColor = FLinearColor(1.0, 1.0, 1.0, 1.0)
                    local midColor = FLinearColor(1.0, 0.54, 0.11, 1.0)
                    local endColor = FLinearColor(1.0, 0.23, 0.15, 1.0)
                    local sliderColor = FPSFineTunePer < 0.4 and startColor or _getColorByPercent(midColor, endColor, (FPSFineTunePer - 0.4) / 0.6)
                    itemRoot.Slider_screen3:SetSliderHandleColor(sliderColor)
                end
            end

            ft_impl.OnFPSFTValueChange3 = function(self, FPSFineTuneNum)
                GraphicSettingDB:UpdateUIData(GraphicSettingDB.FPSFineTuneNum, FPSFineTuneNum)
                if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
                if self:GetParentUI() then self:GetParentUI():SetDirty(true) end
                local gameInstance = GraphicSettingDB.GetGameInstance and GraphicSettingDB.GetGameInstance()
                if gameInstance then
                    gameInstance:ExecuteCMD("t.MaxFPS", tostring(FPSFineTuneNum))
                    gameInstance:ExecuteCMD("r.FrameRateLimit", tostring(FPSFineTuneNum))
                end
            end

            ft_impl.OnFPSFTSliderValueChange3 = function(self, value)
                if GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch) and KismetMathLibrary then
                    local FPSFineTuneNum = KismetMathLibrary.FCeil(value * (165 - NMinFPS) / NStep) * NStep + NMinFPS
                    self:OnFPSFTValueChange3(clamp(FPSFineTuneNum, NMinFPS, 165))
                end
            end
            
            ft_impl.OnFPSFTAdd = ft_impl.OnFPSFTAdd3
            ft_impl.OnFPSFTMinus = ft_impl.OnFPSFTMinus3
            ft_impl.OnFPSFTAdd2 = ft_impl.OnFPSFTAdd3
            ft_impl.OnFPSFTMinus2 = ft_impl.OnFPSFTMinus3
            ft_impl.OnFPSFTSliderValueChange = ft_impl.OnFPSFTSliderValueChange3
            ft_impl.OnFPSFTSliderValueChange2 = ft_impl.OnFPSFTSliderValueChange3
        end
    end)
    _G.ZEXYGODXState.GraphicsUnlocked = true
    Notify("Graphics & FPS 165Hz Unlocked (Upgraded Version)")
end

-- ========================================== 
-- MULAI BUAT SISTEM SISTEM ESP (ASLI)
-- ========================================== 
local function InitializeNativeESP() 
    if _G.ZEXYGODXState.NativeESPReady then return end
    pcall(function() 
        local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools") 
        local currentMarkCfg = GamePlayTools.GetCurrentConfig("ScreenMarkConfig") 
        local function ApplyCfg(cfg)
            if not cfg then return end 
            if cfg[1006] then 
                cfg[1006].bBindBlocked = true;
                cfg[1006].bBindOutScreen = true; 
                cfg[1006].MaxWidgetNum = 99
                cfg[1006].MaxShowDistance = 6000000; 
                cfg[1006].bScaleByDistance = false
                cfg[1006].BindSocketName = "root"; 
                cfg[1006].bUseLuaWorldSocketName = true
                cfg[1006].WorldPositionOffset = FVector(0, 0, -30) 
            end 
            -- [FIX ESP JENIS 4] Thay karena gunakan 1003 mudah terkena game hapus, ta buat ID unik hak 8888
            cfg[8888] = { 
                UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                MaxWidgetNum = 99, 
                MaxShowDistance = 6000000, 
                bBindOutScreen = true,
                bBindBlocked = true, 
                bIsBindingActor = true,     -- Wajib wajib harus ada untuk mengikuti theo musuh
                BindSocketName = "head",
                bUseLuaWorldSocketName = true, 
                WorldPositionOffset = FVector(0, 0, 30),
                bNeedPreLoad = true,        -- Wajib wajib ada untuk load siap UI (anti error)
                Priority = 2 
            } 
            cfg[9999] = { 
                UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                MaxWidgetNum = 99, 
                MaxShowDistance = 6000000, 
                bBindOutScreen = true,
                bBindBlocked = true, 
                bIsBindingActor = true, 
                BindSocketName = "head",
                bUseLuaWorldSocketName = true, 
                WorldPositionOffset = FVector(0, 0, 50),
                bNeedPreLoad = true, 
                Priority = 2 
            } 
        end 
        ApplyCfg(currentMarkCfg) 
        for k, cfg in pairs(package.loaded) do 
            if type(k) == "string" and string.find(k, "ScreenMarkConfig") and type(cfg) == "table" then 
                ApplyCfg(cfg) 
            end 
        end 
    end)
    _G.ZEXYGODXState.NativeESPReady = true 
    Notify("Native ESP System Initialized") 
end

-- ========================================== 
-- LOCAL FUNCTIONS CHO LOGIC NEW ESP - OPTIMIZED
-- ========================================== 
local function GetAllSkeletalMeshes(enemy, markData)
    local curTime = os.clock()
    -- [FIX CRASH GAME]: Kurangi waktu gian Cache turun 0.5s. Pertahankan 3.0s Bot mati Mesh hilang hilang akan menyebabkan Crash C++
    if markData and markData.CachedMeshes and markData.CachedMeshTime and (curTime - markData.CachedMeshTime < 0.5) then
        local validMeshes = {}
        for _, cachedMesh in ipairs(markData.CachedMeshes) do
            -- Periksa tra tambahan kondisi aksesori IsPendingKill untuk pastikan pasti Mesh belum terkena game hapus
            local isPendingKill = false
            pcall(function() if type(cachedMesh.IsPendingKill) == "function" then isPendingKill = cachedMesh:IsPendingKill() end end)
            
            if Valid(cachedMesh) and not isPendingKill then 
                table.insert(validMeshes, cachedMesh) 
            end
        end
        markData.CachedMeshes = validMeshes
        return validMeshes
    end

    local meshes = {}
    if Valid(enemy.Mesh) then table.insert(meshes, enemy.Mesh) end
    pcall(function()
        local SkeletalMeshClass = import("SkeletalMeshComponent")
        if SkeletalMeshClass and type(enemy.GetComponentsByClass) == "function" then
            local childs = enemy:GetComponentsByClass(SkeletalMeshClass)
            if childs then
                local count = type(childs.Num) == "function" and childs:Num() or #childs
                for i = 1, count do
                    local comp = type(childs.Get) == "function" and childs:Get(i-1) or childs[i]
                    if Valid(comp) and comp ~= enemy.Mesh then
                        table.insert(meshes, comp)
                    end
                end
            end
        end
    end)
    if markData then
        markData.CachedMeshes = meshes
        markData.CachedMeshTime = curTime
    end
    return meshes
end

-- ========================================== 
-- FUNGSI TEMBUS DINDING & RESTORE ASLI
-- ==========================================
local function UndoWallXuyenTuong(enemy, markData)
    pcall(function()
        if markData.WallhackApplied then
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            for _, mesh in ipairs(meshes) do
                if Valid(mesh) then
                    pcall(function() if type(mesh.SetRenderCustomDepth) == "function" then mesh:SetRenderCustomDepth(false) end end)
                    for i = 0, 10 do 
                        local matInterface = mesh:GetMaterial(i)
                        if Valid(matInterface) then
                            local baseMat = matInterface:GetBaseMaterial()
                            if Valid(baseMat) then baseMat.bDisableDepthTest = false end
                        end
                    end
                end
            end
            markData.WallhackApplied = false
        end
    end)
end

local function ApplyWallXuyenTuong(enemy, markData)
    pcall(function()
        local meshes = GetAllSkeletalMeshes(enemy, markData)
        for _, mesh in ipairs(meshes) do
            if Valid(mesh) then 
                pcall(function()
                    if type(mesh.SetRenderCustomDepth) == "function" then
                        mesh:SetRenderCustomDepth(true)
                    end
                    if type(mesh.SetCustomDepthStencilValue) == "function" then
                        mesh:SetCustomDepthStencilValue(252) 
                    end
                end)
                for i = 0, 10 do 
                    local matInterface = mesh:GetMaterial(i)
                    if not Valid(matInterface) then break end
                    local baseMat = matInterface:GetBaseMaterial()
                    if Valid(baseMat) then
                        baseMat.bDisableDepthTest = true
                        baseMat.BlendMode = 2 
                    end
                end
            end
        end
    end)
end

local function ApplyColorBodyV2(enemy, pc, markData)
    pcall(function()
        local meshes = GetAllSkeletalMeshes(enemy, markData)
        if #meshes == 0 then return end
        
        -- [FIX ANTI LAG LAG RAMAI PEMAIN]: Batas batas tia Raycast Check Dinding 0.3s satu kali
        -- Hindari agar menembak ribuan ribuan tia fisika fisika setiap detik membuat membebani CPU
        local curTime = os.clock()
        if markData.LastVisCheckTime == nil or (curTime - markData.LastVisCheckTime) > 0.3 then
            markData.LastVisCheckTime = curTime
            local isHidden = true
            pcall(function()
                if Valid(pc) and type(pc.LineOfSightTo) == "function" then
                    if pc:LineOfSightTo(enemy) then isHidden = false else isHidden = true end
                end
            end)
            markData.CachedHiddenState = isHidden
        end
        
        local hidden = markData.CachedHiddenState
        if hidden == nil then hidden = true end
        
        local cData = _G.ZEXYGODXState.CustomTextData or {}
        local hiddenColor = {R = cData.HiddenR or 150, G = cData.HiddenG or 0, B = cData.HiddenB or 0, A = cData.HiddenA or 25}
        local visibleColor = {R = cData.VisibleR or 0, G = cData.VisibleG or 150, B = cData.VisibleB or 0, A = cData.VisibleA or 25}
        
        local finalColor = hidden and hiddenColor or visibleColor
        local colorHash = string.format("%d_%d_%d_%d", finalColor.R, finalColor.G, finalColor.B, finalColor.A)
        local currentMeshCount = #meshes
        local isMeshChanged = (markData.LastMeshCount ~= currentMeshCount)
        
        -- Jika belum ada perubahan ubah warna / ubah jumlah jumlah pakaian pakaian maka hentikan selalu, hemat hemat CPU
        if not isMeshChanged and markData.LastHiddenState == hidden and markData.LastColorHash == colorHash then return end
        
        -- [FIX RAM]: Hapus Material sampah lama pergi khi musuh ubah senjata senjata/pakaian armor untuk hindari sampah VRAM
        if isMeshChanged and markData.MIDs then
            markData.MIDs = {}
        end

        markData.LastHiddenState = hidden
        markData.LastMeshCount = currentMeshCount
        markData.LastColorHash = colorHash
        markData.ColorApplied = true
        
        for meshIndex, mesh in ipairs(meshes) do
            if Valid(mesh) then
                pcall(function()
                    mesh.LDMaxDrawDistance = -99999
                    mesh.MaxDrawDistanceOffset = -99999
                    mesh.CachedMaxDrawDistance = -99999
                    mesh.UseScopeDistanceCulling = true
                    mesh.PrimitiveShadingStrategy = 1
                    mesh.ShadingRate = 6
                end)
                for i = 0, 10 do
                    local matInterface = mesh:GetMaterial(i)
                    if not Valid(matInterface) then break end
                    local baseMat = matInterface:GetBaseMaterial()
                    if Valid(baseMat) then
                        local matName = tostring(baseMat)
                        if string.find(matName, "Master_Mask", 1, true) then
                            if not markData.MIDs then markData.MIDs = {} end
                            
                            -- [FIX SAMPAH RAM]: Thay karena gunakan tostring(mesh) sinh sampah string, gunakan index lokal lokal
                            local meshKey = "Mesh_" .. tostring(meshIndex)
                            
                            if not markData.MIDs[meshKey] then markData.MIDs[meshKey] = {} end
                            local mid = markData.MIDs[meshKey][i]
                            if not Valid(mid) then
                                mid = mesh:CreateAndSetMaterialInstanceDynamic(i)
                                markData.MIDs[meshKey][i] = mid
                            end
                            if Valid(mid) then
                                mid:SetVectorParameterValue("颜色", finalColor)
                                mid:SetVectorParameterValue("Extra Light Color", finalColor)
                                mid:SetVectorParameterValue("Para_Color", finalColor)
                                mid:SetVectorParameterValue("Para_ColorTint", finalColor)
                                mid:SetVectorParameterValue("Para_Color_1", finalColor)
                                mid:SetVectorParameterValue("Tint", finalColor)
                                mid:SetVectorParameterValue("Color", finalColor)
                                mid:SetVectorParameterValue("BaseColor", finalColor)
                                mid:SetVectorParameterValue("BodyColor", finalColor)
                                mid:SetVectorParameterValue("MainColor", finalColor)
                                mid:SetVectorParameterValue("DiffuseColor", finalColor)
                                mid:SetVectorParameterValue("EmissiveColor", finalColor)
                                mid:SetVectorParameterValue("ParaScaleOffset", SCALE_COLOR_V2)
                            end
                        end
                    end
                end
            end
        end
    end)
end

local function UndoColorBodyV2(enemy, markData)
    pcall(function()
        if markData.ColorApplied then
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            for meshIndex, mesh in ipairs(meshes) do
                if Valid(mesh) then
                    pcall(function()
                        mesh.PrimitiveShadingStrategy = 0
                        mesh.ShadingRate = 1
                    end)
                    local meshKey = "Mesh_" .. tostring(meshIndex)
                    if markData.MIDs and markData.MIDs[meshKey] then
                        for i, mid in pairs(markData.MIDs[meshKey]) do
                            if Valid(mid) then
                                local defC = {R=1, G=1, B=1, A=1}
                                mid:SetVectorParameterValue("颜色", defC)
                                mid:SetVectorParameterValue("Extra Light Color", defC)
                                mid:SetVectorParameterValue("Para_Color", defC)
                                mid:SetVectorParameterValue("Para_ColorTint", defC)
                                mid:SetVectorParameterValue("Para_Color_1", defC)
                                mid:SetVectorParameterValue("Tint", defC)
                                mid:SetVectorParameterValue("Color", defC)
                                mid:SetVectorParameterValue("BaseColor", defC)
                                mid:SetVectorParameterValue("BodyColor", defC)
                                mid:SetVectorParameterValue("MainColor", defC)
                                mid:SetVectorParameterValue("DiffuseColor", defC)
                                mid:SetVectorParameterValue("EmissiveColor", defC)
                            end
                        end
                    end
                end
            end
            markData.ColorApplied = false
            markData.LastColorHash = ""
            markData.LastHiddenState = nil
        end
    end)
end

-- ==========================================
-- FITUR FITUR WARNA V3 (PISAHKAN KHUSUS DARI KODE SUMBER MILIK ANDA - AKTIF OTOMATIS QUA PAKET CACHE Z-BUFFER)
-- [SUDAH FIX ERROR HILANG WARNA KHI UBAH LOD & MAKSIMAL OPTIMASI ANTI DROP FPS KHI RAMAI PEMAIN]
-- ==========================================
local function ApplyColorBodyV3(enemy, markData)
    pcall(function()
        local meshes = GetAllSkeletalMeshes(enemy, markData)
        if #meshes == 0 then return end
        
        local cData = _G.ZEXYGODXState.CustomTextData or {}
        local hidChoice = cData.ColorV3Hidden or 1
        local visChoice = cData.ColorV3Visible or 2
        local v3Thick = cData.ColorV3Thickness or 4
        
        -- Buat kode hash untuk terang tampilkan pemain gunakan geser thanh ubah warna/nilai ketebalan
        local currentHash = string.format("%d_%d_%d", hidChoice, visChoice, v3Thick)
        local colorChanged = (markData.LastColorV3Hash ~= currentHash)
        markData.LastColorV3Hash = currentHash

        local function GetColorRGB(choice)
            if choice == 1 then return 255, 0, 0 end -- Merah
            if choice == 2 then return 0, 255, 0 end -- Pistol
            if choice == 3 then return 0, 0, 255 end -- Lam
            if choice == 4 then return 255, 255, 0 end -- Kuning
            if choice == 5 then return 255, 0, 255 end -- Ungu/Merah muda
            if choice == 6 then return 255, 255, 255 end -- Putih
            return 255, 0, 0 -- Default tetapkan merah
        end

        local hR, hG, hB = GetColorRGB(hidChoice)
        local vR, vG, vB = GetColorRGB(visChoice)

        -- Warna Sau Dinding (invisColor)
        local invisColor = { R=hR, G=hG, B=hB, A=255, r=hR, g=hG, b=hB, a=255 }
        
        -- Warna Outline Terlihat Tampilan HDR (visColor)
        local glowIntensity = 80.0 
        local LinearColorClass = import("LinearColor") or _G.FLinearColor
        local visColor = LinearColorClass and LinearColorClass((vR/255)*glowIntensity, (vG/255)*glowIntensity, (vB/255)*glowIntensity, 1.0) or { R=vR*glowIntensity, G=vG*glowIntensity, B=vB*glowIntensity, A=255 }
        local scale = { R=3.0, G=3.0, B=0.0, A=0.0, r=3.0, g=3.0, b=0.0, a=0.0 }
        
        markData.MIDs_V3 = markData.MIDs_V3 or {}

        for meshIndex, comp in ipairs(meshes) do
            if Valid(comp) then
                local compKey = "MeshV3_" .. tostring(meshIndex)
                markData.MIDs_V3[compKey] = markData.MIDs_V3[compKey] or {}
                
                pcall(function()
                    if comp.PrimitiveShadingStrategy ~= 1 then
                        comp.UseScopeDistanceCulling = false 
                        comp.PrimitiveShadingStrategy = 1
                        comp.ShadingRate = 6
                    end
                end)
                
                for i = 0, 10 do
                    local matInterface = comp:GetMaterial(i)
                    if not Valid(matInterface) then break end
                    
                    local baseMat = matInterface:GetBaseMaterial()
                    if Valid(baseMat) then
                        if baseMat.bDisableDepthTest ~= true then baseMat.bDisableDepthTest = true end
                        if baseMat.BlendMode ~= 2 then baseMat.BlendMode = 2 end
                    end
                    
                    local currentCached = markData.MIDs_V3[compKey][i]
                    local needUpdateColor = false
                    
                    -- Jika belum ada MID atau pemain gunakan geser thanh ubah warna -> Perbarui perbarui lagi
                    if not Valid(currentCached) then
                        local newMid = comp:CreateAndSetMaterialInstanceDynamic(i)
                        if Valid(newMid) then 
                            markData.MIDs_V3[compKey][i] = newMid
                            currentCached = newMid
                            needUpdateColor = true
                        end
                    elseif colorChanged then
                        needUpdateColor = true
                    end
                    
                    if Valid(currentCached) and needUpdateColor then
                        pcall(function()
                            currentCached:SetVectorParameterValue("颜色", invisColor)
                            currentCached:SetVectorParameterValue("Extra Light Color", invisColor)
                            currentCached:SetVectorParameterValue("Para_Color", invisColor)
                            currentCached:SetVectorParameterValue("Para_ColorTint", invisColor)
                            currentCached:SetVectorParameterValue("Para_Color_1", invisColor)
                            currentCached:SetVectorParameterValue("Tint", invisColor)
                            currentCached:SetVectorParameterValue("Color", invisColor)
                            currentCached:SetVectorParameterValue("BaseColor", invisColor)
                            currentCached:SetVectorParameterValue("BodyColor", invisColor)
                            currentCached:SetVectorParameterValue("MainColor", invisColor)
                            currentCached:SetVectorParameterValue("DiffuseColor", invisColor)
                            currentCached:SetVectorParameterValue("EmissiveColor", invisColor)
                            currentCached:SetVectorParameterValue("CustomColor", invisColor)
                            currentCached:SetVectorParameterValue("OverlayColor", invisColor)
                            currentCached:SetVectorParameterValue("GlowColor", invisColor)
                            currentCached:SetVectorParameterValue("EdgeColor", invisColor)
                            currentCached:SetVectorParameterValue("LightColor", invisColor)
                            currentCached:SetVectorParameterValue("OutlineColor", invisColor)
                            currentCached:SetVectorParameterValue("ParaScaleOffset", scale)
                            currentCached:SetScalarParameterValue("Opacity", 0.7)
                            currentCached:SetScalarParameterValue("Alpha", 0.7)
                            currentCached:SetScalarParameterValue("GlowIntensity", 1.0)
                            currentCached:SetScalarParameterValue("Intensity", 1.0)
                        end)
                    end
                end
                
                pcall(function()
                    if comp.SetDrawIdeaOutline then
                        comp:SetDrawIdeaOutline(true)
                        if comp.OverrideIdeaOutlineColor then comp:OverrideIdeaOutlineColor(true, visColor) end
                        if comp.OverrideIdeaOutlineThickness then comp:OverrideIdeaOutlineThickness(true, v3Thick) end
                    end
                end)
            end
        end
        markData.ColorV3Applied = true
    end)
end

local function UndoColorBodyV3(enemy, markData)
    pcall(function()
        if markData.ColorV3Applied then
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            for meshIndex, comp in ipairs(meshes) do
                if Valid(comp) then
                    pcall(function()
                        comp.PrimitiveShadingStrategy = 0
                        comp.ShadingRate = 1
                    end)
                    
                    for i = 0, 10 do
                        local s, matInterface = pcall(function() return comp:GetMaterial(i) end)
                        if s and Valid(matInterface) then
                            local s2, baseMat = pcall(function() return matInterface:GetBaseMaterial() end)
                            if s2 and Valid(baseMat) then
                                baseMat.bDisableDepthTest = false
                                baseMat.BlendMode = 1
                            end
                        end
                    end
                    
                    local compKey = "MeshV3_" .. tostring(meshIndex)
                    if markData.MIDs_V3 and markData.MIDs_V3[compKey] then
                        for i, mid in pairs(markData.MIDs_V3[compKey]) do
                            if Valid(mid) then
                                pcall(function()
                                    local defC = {R=1, G=1, B=1, A=1, r=1, g=1, b=1, a=1}
                                    mid:SetVectorParameterValue("颜色", defC)
                                    mid:SetVectorParameterValue("Extra Light Color", defC)
                                    mid:SetVectorParameterValue("Para_Color", defC)
                                    mid:SetVectorParameterValue("Tint", defC)
                                    mid:SetVectorParameterValue("BaseColor", defC)
                                    mid:SetVectorParameterValue("Color", defC)
                                end)
                            end
                        end
                    end
                    
                    pcall(function()
                        if comp.SetDrawIdeaOutline then
                            comp:SetDrawIdeaOutline(false)
                        end
                    end)
                end
            end
            markData.ColorV3Applied = false
            markData.LastMeshCountV3 = 0 -- Reset lokal hitung mesh untuk ada bisa aktifkan lagi sau
            if markData.MIDs_V3 then markData.MIDs_V3 = nil end
        end
    end)
end
-- ==========================================
-- FITUR FITUR WALL WARNA NEW (TELAH SAMA PAKET KE SISTEM SISTEM VIP MAKSIMAL OPTIMASI)
-- ==========================================
local function ApplyColorBodyNew(enemy, markData)
    pcall(function()
        -- Aktifkan aktifkan Console Command jika belum aktifkan (Hanya panggil 1 kali)
        if not _G.ConsoleNewWallReady then
            local KismetSystemLibrary = import("KismetSystemLibrary")
            local world = slua.getWorld()
            if KismetSystemLibrary and world then
                KismetSystemLibrary.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
                KismetSystemLibrary.ExecuteConsoleCommand(world, "r.CustomDepth 3")
                KismetSystemLibrary.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
                KismetSystemLibrary.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
                _G.ConsoleNewWallReady = true
            end
        end

        -- Ambil semua lokal Mesh milik musuh musuh
        local meshes = GetAllSkeletalMeshes(enemy, markData)
        
        -- Tambahkan mesh milik senjata senjata sedang memegang di tay
        local weapon = nil
        pcall(function() weapon = enemy:GetCurrentWeapon() end)
        if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
            table.insert(meshes, weapon.Mesh)
        end

        local isBot = markData.AK_IS_BOT or false
        local currentMeshCount = #meshes
        
        -- [MAKSIMAL OPTIMASI FPS MAKSIMAL MUTLAK] - MODE TINGKAT TIDUR RAMAI (CACHE)
        -- Buat kode hash deteksi terlihat: Jika jumlah jumlah pakaian pakaian/senjata milik musuh tidak ubah, abaikan qua loop ulang C++ sangat berat bagian bawah
        local stateHash = (isBot and "BOT" or "PLAYER") .. "_" .. tostring(currentMeshCount)
        
        if markData.LastColorNewHash == stateHash and markData.ColorNewApplied then
            return -- Semua hal sudah dapat warnai warna sebelumnya itu, hentikan fungsi di ini untuk hindari membebani CPU!
        end
        
        -- Jika ada perubahan thay ubah (baru aktifkan, musuh ubah senjata, ambil barang), lanjut jalankan perbarui perbarui warna dan tersimpan Cache
        markData.LastColorNewHash = stateHash
        markData.ColorNewApplied = true

        -- Hanya Load lokal warna khi sebenarnya perubahan perlu proses fisika
        local LinearColorClass = import("LinearColor") or _G.FLinearColor
        local c_vis = LinearColorClass and LinearColorClass(0, 100, 0, 1) or {R=0, G=100, B=0, A=1}
        local c_occ = LinearColorClass and LinearColorClass(100, 0, 0, 1) or {R=100, G=0, B=0, A=1}
        local c_bVis = LinearColorClass and LinearColorClass(49, 48, 0, 100) or {R=49, G=48, B=0, A=100}
        local c_bOcc = LinearColorClass and LinearColorClass(9, 1.5, 45, 100) or {R=9, G=1.5, B=45, A=100}

        local visColor = isBot and c_bVis or c_vis
        local occColor = isBot and c_bOcc or c_occ

        for _, mesh in ipairs(meshes) do
            if Valid(mesh) then
                pcall(function()
                    if type(mesh.SetDrawDyeing) == "function" then
                        mesh:SetDrawDyeing(true)
                        mesh:SetDrawDyeingMode(1)
                        mesh:SetVisibleDyeingColor(visColor)
                        mesh:SetOccludedDyeingColor(occColor)
                        mesh:SetDyeingColorFadeDistance(99999.0)
                        mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0)
                        mesh:SetDrawHighlight(true)
                        mesh:OverrideHighlightColor(visColor)
                        mesh:SetHighlightCanBeOccluded(false)
                        mesh:SetDrawIdeaOutline(true)
                        mesh:SetIdeaOutlineNew(true)
                        mesh:SetIdeaOutlineOcclusionHighlight(true)
                        mesh:OverrideIdeaOutlineColor(visColor)
                        mesh:SetIdeaOutlineOcclusionColor(occColor)
                        mesh:OverrideIdeaOutlineThickness(20.0)
                        mesh:SetIdeaOverrideOutlineAndOcclusion(true)
                        mesh:SetRenderCustomDepth(true)
                        mesh:SetCustomDepthStencilValue(255)
                    end
                end)
            end
        end
    end)
end

local function UndoColorBodyNew(enemy, markData)
    pcall(function()
        if markData.ColorNewApplied then
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            local weapon = nil
            pcall(function() weapon = enemy:GetCurrentWeapon() end)
            if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
                table.insert(meshes, weapon.Mesh)
            end

            for _, mesh in ipairs(meshes) do
                if Valid(mesh) then
                    pcall(function()
                        if type(mesh.SetDrawDyeing) == "function" then
                            mesh:SetDrawDyeing(false)
                            mesh:SetDrawHighlight(false)
                            mesh:SetDrawIdeaOutline(false)
                            mesh:SetRenderCustomDepth(false)
                        end
                    end)
                end
            end
            markData.ColorNewApplied = false
            markData.LastColorNewHash = "" -- Hapus Cache untuk kali sau aktifkan lagi akan hitung hitung lagi halus yang
        end
    end)
end

-- ========================================== 
-- SISTEM SISTEM AIMBOT V2 INTEGRASI GABUNG BARU (UPDATE KISMET SMOOTH)
-- ========================================== 
_G.GetEnemyTargetsFromActors = function(radius)
    local result = {}
    local player = GameplayData.GetPlayerCharacter()

    if not slua.isValid(player) then
        return result
    end

    local allCharacters = {}
    if GameplayData.GetAllPlayerCharacters then
        allCharacters = GameplayData.GetAllPlayerCharacters()
    elseif GameplayData.GameCharacters then
        for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end
    end

    local myTeam = player:GetTeamID()

    for _, actor in pairs(allCharacters) do
        if slua.isValid(actor) and actor ~= player and actor.GetTeamID and actor:IsAlive() then
            if actor:GetTeamID() ~= myTeam then
                local dist = player:GetDistanceTo(actor)
                if dist <= radius then
                    table.insert(result, actor)
                end
            end
        end
    end
    return result
end

_G.AimTouch = function()
    pcall(function()
        if not _G.ZEXYGODXConfig.AimTouchEnable then return end
        
        local player = GameplayData.GetPlayerCharacter()
        if not slua.isValid(player) then return end
        
        local pc = player:GetPlayerControllerSafety()
        if not slua.isValid(pc) then return end
        
        local isFiring = player.bIsWeaponFiring
        local isADS = player.bIsGunADS
        
        -- CHECK WEAPON & AMMO
        local weapon = player.WeaponManagerComponent and player.WeaponManagerComponent.CurrentWeaponReplicated
        if not weapon and type(player.GetCurrentShootWeapon) == "function" then
            weapon = player:GetCurrentShootWeapon()
        end
        
        local isShotgun = false
        local isSniper = false
        local isMortar = false
        local currentAmmo = 1
        
        if slua.isValid(weapon) then
            local wID = type(weapon.GetWeaponID) == "function" and weapon:GetWeaponID() or 0
            local wName = type(weapon.GetWeaponName) == "function" and weapon:GetWeaponName() or ""
            
            if (wID >= 1030000 and wID < 1040000) or wName:find("S686") or wName:find("S1897") or wName:find("S12") or wName:find("DBS") or wName:find("M1014") then 
                isShotgun = true 
            end
            
            if wName:find("Kar98") or wName:find("M24") or wName:find("AWM") or wName:find("Mosin") or wName:find("Win94") or wName:find("AMR") or wName:find("SKS") or wName:find("SLR") or wName:find("Mini") or wName:find("Mk14") or wName:find("QBU") or wName:find("Mk12") or wName:find("VSS") then
                isSniper = true
            end

            if wName:lower():find("mortar") or wName:lower():find("cối") then
                isMortar = true
            end
            
            if type(weapon.GetCurrentAmmo) == "function" then
                currentAmmo = weapon:GetCurrentAmmo()
            elseif weapon.ShootWeaponComponent and type(weapon.ShootWeaponComponent.GetCurrentAmmo) == "function" then
                currentAmmo = weapon.ShootWeaponComponent:GetCurrentAmmo()
            elseif weapon.CurrentAmmo ~= nil then
                currentAmmo = weapon.CurrentAmmo
            end
        end

        -- LOGIC LEPAS PEMICU SENJATA JIKA HILANG DIREKTORI TARGET / MUSUH MATI ATAU SHOTGUN HABIS PELURU
        if _G.ZEXYGODXState.IsAutoFiring then
            pcall(function()
                player.bIsWeaponFiring = false
                if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(false) end
                if slua.isValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(false) end
                local wepMgr = player.WeaponManagerComponent
                if slua.isValid(wepMgr) then wepMgr.bIsWeaponFiring = false end
            end)
            _G.ZEXYGODXState.IsAutoFiring = false
        end

        -- SHOTGUN HABIS PELURU HENTIKAN AIM UNTUK GAME ISI ULANG PELURU
        if isShotgun and currentAmmo <= 0 then
            return
        end

        local cond = 2
        local prioMode = 1
        local boneIdx = 1
        local speedVal = 50
        local fovVal = 30
        local maxDistMeters = 50
        local useVisCheck = false
        local igKnock = false
        local igBot = false
        
        -- Logic tambahan ke: Prediksi prediksi dan Kompensasi lag
        local predVal = 0 
        local recoilCompVal = 0 

        -- KLASIFIKASI JENIS KONFIGURASI KONFIGURASI THEO STATUS STATUS SAAT INI SAAT INI
        if isMortar and _G.ZEXYGODXConfig.AimTouchMortar then
            local isPlaced = false
            pcall(function()
                if weapon and weapon.MortarState == 2 then isPlaced = true end
            end)
            if not isPlaced then return end

            cond = 2 
            prioMode = 1  
            boneIdx = 4 
            speedVal = 100 
            fovVal = _G.ZEXYGODXState.CustomTextData.AimTouchMortarFOV or 360 
            maxDistMeters = 2000 
            useVisCheck = false 
            igKnock = false
            igBot = false
            predVal = _G.ZEXYGODXState.CustomTextData.AimTouchMortarPred or 0 
            
        elseif isShotgun and _G.ZEXYGODXConfig.AimTouchSG then
            cond = _G.ZEXYGODXState.CustomTextData.AimTouchSGCond or 1
            if _G.ZEXYGODXConfig.AimTouchSGAutoFire then cond = 2 end
            if cond == 1 and not isFiring then return end
            prioMode = _G.ZEXYGODXState.CustomTextData.AimTouchSGPrio or 1
            boneIdx = _G.ZEXYGODXState.CustomTextData.AimTouchSGBone or 2
            speedVal = _G.ZEXYGODXState.CustomTextData.AimTouchSGSpeed or 80
            fovVal = _G.ZEXYGODXState.CustomTextData.AimTouchSGFOV or 40
            maxDistMeters = _G.ZEXYGODXState.CustomTextData.AimTouchSGDist or 30
            useVisCheck = _G.ZEXYGODXConfig.AimTouchSGVisCheck
            igKnock = _G.ZEXYGODXConfig.AimTouchSGIgKnock
            igBot = _G.ZEXYGODXConfig.AimTouchSGIgBot
            
        elseif isADS then
            if isSniper and _G.ZEXYGODXConfig.AimTouchScopeSniper then
                cond = _G.ZEXYGODXState.CustomTextData.AimTouchSniperCond or 2
                if cond == 1 and not isFiring then return end
                prioMode = _G.ZEXYGODXState.CustomTextData.AimTouchSniperPrio or 1
                boneIdx = _G.ZEXYGODXState.CustomTextData.AimTouchSniperBone or 1
                speedVal = _G.ZEXYGODXState.CustomTextData.AimTouchSniperSpeed or 30
                fovVal = _G.ZEXYGODXState.CustomTextData.AimTouchSniperFOV or 20
                maxDistMeters = _G.ZEXYGODXState.CustomTextData.AimTouchSniperDist or 400
                useVisCheck = _G.ZEXYGODXConfig.AimTouchSniperVisCheck
                igKnock = _G.ZEXYGODXConfig.AimTouchSniperIgKnock
                igBot = _G.ZEXYGODXConfig.AimTouchSniperIgBot
                predVal = _G.ZEXYGODXState.CustomTextData.AimTouchSniperPred or 0 -- Ambil nilai nilai prediksi prediksi Sniper
            elseif _G.ZEXYGODXConfig.AimTouchScopeAll then
                cond = _G.ZEXYGODXState.CustomTextData.AimTouchScopeCond or 1
                if cond == 1 and not isFiring then return end
                prioMode = _G.ZEXYGODXState.CustomTextData.AimTouchScopePrio or 1
                boneIdx = _G.ZEXYGODXState.CustomTextData.AimTouchScopeBone or 2
                speedVal = _G.ZEXYGODXState.CustomTextData.AimTouchScopeSpeed or 40
                fovVal = _G.ZEXYGODXState.CustomTextData.AimTouchScopeFOV or 20
                maxDistMeters = _G.ZEXYGODXState.CustomTextData.AimTouchScopeDist or 300
                useVisCheck = _G.ZEXYGODXConfig.AimTouchScopeVisCheck
                igKnock = _G.ZEXYGODXConfig.AimTouchScopeIgKnock
                igBot = _G.ZEXYGODXConfig.AimTouchScopeIgBot
                predVal = _G.ZEXYGODXState.CustomTextData.AimTouchScopePred or 0 -- Ambil nilai nilai prediksi prediksi Senjata biasa
                recoilCompVal = _G.ZEXYGODXState.CustomTextData.AimTouchScopeRecoil or 0 -- Ambil nilai nilai kompensasi lag
            else
                return
            end
        else
            if not _G.ZEXYGODXConfig.AimTouchHipfire then return end
            cond = _G.ZEXYGODXState.CustomTextData.AimTouchHipCond or 1
            if cond == 1 and not isFiring then return end 
            prioMode = _G.ZEXYGODXState.CustomTextData.AimTouchHipPrio or 1
            boneIdx = _G.ZEXYGODXState.CustomTextData.AimTouchHipBone or 1
            speedVal = _G.ZEXYGODXState.CustomTextData.AimTouchHipSpeed or 50
            fovVal = _G.ZEXYGODXState.CustomTextData.AimTouchHipFOV or 30
            maxDistMeters = _G.ZEXYGODXState.CustomTextData.AimTouchHipDist or 250
            useVisCheck = _G.ZEXYGODXConfig.AimTouchHipVisCheck
            igKnock = _G.ZEXYGODXConfig.AimTouchHipIgKnock
            igBot = _G.ZEXYGODXConfig.AimTouchHipIgBot
        end

        local currentMaxDist = maxDistMeters * 100 

        local enemies = _G.GetEnemyTargetsFromActors(currentMaxDist)
        if not enemies or #enemies == 0 then return end
        
        local FVector2D = import("Vector2D")
        local UGameplayStatics = import("GameplayStatics")
        local KismetMathLibrary = import("KismetMathLibrary")
        
        local camManager = UGameplayStatics.GetPlayerCameraManager(pc, 0)
        if not slua.isValid(camManager) then return end
        
        local camLoc = camManager:GetCameraLocation()
        if not camLoc then return end
        
        local ui_util = require("client.common.ui_util")
        if not ui_util then return end
        
        local viewportSize = ui_util.GetViewportSize()
        if not viewportSize then return end
        
        local centerX = viewportSize.X * 0.5
        local centerY = viewportSize.Y * 0.5
        
        local FOV_RADIUS = (fovVal / 100.0) * (viewportSize.X / 2.0)
        
        local bestTarget = nil
        local bestScore = 99999999 
        
        local selBoneName = "head"
        if boneIdx == 1 then selBoneName = "head"
        elseif boneIdx == 2 then selBoneName = "spine_03"
        elseif boneIdx == 3 then selBoneName = "spine_01"
        elseif boneIdx == 4 then selBoneName = "pelvis" end

        for i, target in ipairs(enemies) do
            if not slua.isValid(target) then goto continue end
            
            pcall(function()
                if slua.isValid(target.Mesh) then
                    target.Mesh.MeshComponentUpdateFlag = 0
                end
            end)
            
            if igKnock and target.HealthStatus == 1 then goto continue end
            
            if igBot then
                local tIsBot = false
                if target.bIsAI == true or target.IsAI == true then tIsBot = true end
                local pState = target.PlayerState
                if slua.isValid(pState) and (pState.bIsABot or pState.bIsBot) then tIsBot = true end
                if tIsBot then goto continue end
            end
            
            -- [FIX TURUN FPS]: Kunci tia Raycast check dinding, hanya scan 0.2s satu kali (Cukup halus yang tidak membebani CPU)
            if useVisCheck then
                local curTime = os.clock()
                local tId = type(target.GetUniqueID) == "function" and target:GetUniqueID() or tostring(target)
                _G.AimTouchVisCache = _G.AimTouchVisCache or {}
                if not _G.AimTouchVisCache[tId] or (curTime - _G.AimTouchVisCache[tId].time) > 0.2 then
                    local isHidden = true
                    pcall(function() if pc:LineOfSightTo(target) then isHidden = false end end)
                    _G.AimTouchVisCache[tId] = { hidden = isHidden, time = curTime }
                end
                if _G.AimTouchVisCache[tId].hidden then goto continue end
            end
            
            local tPos = target:GetBonePos(selBoneName, {X=0, Y=0, Z=0})
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
                if type(target.GetSocketLocation) == "function" then
                    tPos = target:GetSocketLocation(selBoneName)
                end
            end
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
                if type(target.K2_GetActorLocation) == "function" then
                    tPos = target:K2_GetActorLocation()
                    if tPos then
                        if boneIdx == 1 then tPos.Z = tPos.Z + 70
                        elseif boneIdx == 2 then tPos.Z = tPos.Z + 40
                        elseif boneIdx == 3 then tPos.Z = tPos.Z + 20 end
                    end
                end
            end
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then goto continue end
            
            local screen = FVector2D()
            local success = pc:ProjectWorldLocationToScreen(tPos, screen, false)
            if not success or screen.X <= 0 or screen.Y <= 0 then goto continue end
            
            local dx = screen.X - centerX
            local dy = screen.Y - centerY
            local distScreen = math.sqrt(dx*dx + dy*dy)
            
            if distScreen > FOV_RADIUS then goto continue end
            
            local currentScore = distScreen
            if prioMode == 2 then currentScore = player:GetDistanceTo(target)
            elseif prioMode == 3 then currentScore = target.Health or 100
            elseif prioMode == 4 then 
                local hp = target.Health or 100
                local maxhp = target.HealthMax or 100
                if maxhp <= 0 then maxhp = 100 end
                currentScore = hp / maxhp
            end
            
            if currentScore < bestScore then
                bestScore = currentScore
                bestTarget = target
            end
            
            ::continue::
        end
        
        if not slua.isValid(bestTarget) then return end
        
        local finalBonePos = bestTarget:GetBonePos(selBoneName, {X=0, Y=0, Z=0})
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then
            if type(bestTarget.GetSocketLocation) == "function" then
                finalBonePos = bestTarget:GetSocketLocation(selBoneName)
            end
        end
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then
            if type(bestTarget.K2_GetActorLocation) == "function" then
                finalBonePos = bestTarget:K2_GetActorLocation()
                if finalBonePos then
                    if boneIdx == 1 then finalBonePos.Z = finalBonePos.Z + 70
                    elseif boneIdx == 2 then finalBonePos.Z = finalBonePos.Z + 40
                    elseif boneIdx == 3 then finalBonePos.Z = finalBonePos.Z + 20 end
                end
            end
        end
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then return end
        
        local tVelocity = nil
        pcall(function()
            if type(bestTarget.GetVelocity) == "function" then
                tVelocity = bestTarget:GetVelocity()
            end
        end)

        -- LOGIC PREDIKSI ARAH SENJATA MORTIR
        if isMortar and _G.ZEXYGODXConfig.AimTouchMortar and predVal > 0 then
            pcall(function()
                if tVelocity and (tVelocity.X ~= 0 or tVelocity.Y ~= 0) then
                    local approxDist = player:GetDistanceTo(bestTarget) / 100.0
                    local approxToF = approxDist / 100.0 
                    local predScale = predVal / 50.0
                    finalBonePos.X = finalBonePos.X + (tVelocity.X * approxToF * predScale)
                    finalBonePos.Y = finalBonePos.Y + (tVelocity.Y * approxToF * predScale)
                end
            end)
        end

        -- LOGIC 1: PREDICTION (SENJATA BIASA)
        if not isMortar and predVal > 0 then
            pcall(function()
                -- Jika musuh sedang di alih
                if tVelocity and (tVelocity.X ~= 0 or tVelocity.Y ~= 0) then
                    local distToEnemy = player:GetDistanceTo(bestTarget) / 100.0 -- Jarak jarak meter
                    
                    -- Hitung hitung waktu gian peluru bay (Time-Of-Flight) rasio proporsi sebanding dengan jarak jarak dan hilang transmisi ke
                    -- Sistem jumlah 800.0 mewakili terlihat cho kecepatan nilai peluru jatuh simulasi simulasi, 50.0 adalah tingkat trung rata-rata slider
                    local ToF = (distToEnemy / 800.0) * (predVal / 50.0) 
                    
                    -- Geser alih koordinat nilai Aim ke depan sebelumnya arah gerak
                    finalBonePos.X = finalBonePos.X + (tVelocity.X * ToF)
                    finalBonePos.Y = finalBonePos.Y + (tVelocity.Y * ToF)
                end
            end)
        end

        local rot = KismetMathLibrary.FindLookAtRotation(camLoc, finalBonePos)
        if not rot then return end
        
        local currentRot = pc:GetControlRotation()
        if not currentRot then return end
        
        local deltaYaw = rot.Yaw - currentRot.Yaw
        local deltaPitch = rot.Pitch - currentRot.Pitch
        
        -- [MULAI AWAL FIX] Kompensasi kurangi selisih selisih Camera khi buka scope bidik (ADS) untuk tidak terkena selisih pusat
        if isADS then
            local camRot = nil
            if type(camManager.GetCameraRotation) == "function" then
                camRot = camManager:GetCameraRotation()
            end
            if camRot then
                deltaYaw = deltaYaw - (camRot.Yaw - currentRot.Yaw)
                deltaPitch = deltaPitch - (camRot.Pitch - currentRot.Pitch)
            end
        end
        -- [SELESAI SELESAI FIX]

        if deltaYaw > 180 then deltaYaw = deltaYaw - 360 end
        if deltaYaw < -180 then deltaYaw = deltaYaw + 360 end
        if deltaPitch > 180 then deltaPitch = deltaPitch - 360 end
        if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end
        
        local smoothFactor = 0.0
        if speedVal >= 100 then
            smoothFactor = 1.0
        else
            smoothFactor = (speedVal / 100.0) * 0.3
            if smoothFactor < 0.01 then smoothFactor = 0.01 end
        end
        
        local finalPitch = currentRot.Pitch + (deltaPitch * smoothFactor)
        local finalYaw = currentRot.Yaw + (deltaYaw * smoothFactor)
        
        -- LOGIC 2: RECOIL COMPENSATION (PAKSA CROSSHAIR / KOMPENSASI LAG HINDARI TEMBAK TERLALU AWAL)
        if recoilCompVal > 0 and isFiring then
            local pullDownForce = (recoilCompVal / 50.0) * 1.5 
            finalPitch = finalPitch - pullDownForce
        end
        
        -- LOGIC HITUNG HITUNG SUDUT TEMBAK SEBENARNYA SEBENARNYA CHO SENJATA MORTIR
        if isMortar and _G.ZEXYGODXConfig.AimTouchMortar then
            local targetPos = { X = finalBonePos.X, Y = finalBonePos.Y, Z = finalBonePos.Z }
            local launchPos = camLoc
            pcall(function()
                if player.K2_GetActorLocation then
                    local pLoc = player:K2_GetActorLocation()
                    if pLoc then 
                        launchPos = { X = pLoc.X, Y = pLoc.Y, Z = pLoc.Z + 50 } 
                    end
                end
            end)

            local function CalcMortarTrajectory(V, G, tX, tY, tZ)
                local mDx = math.sqrt((tX - launchPos.X)^2 + (tY - launchPos.Y)^2) - 80 
                if mDx < 500 then mDx = 500 end 
                local mDy = tZ - launchPos.Z
                
                local minVSq = G * (mDy + math.sqrt(mDx*mDx + mDy*mDy))
                if (V * V) < minVSq then
                    V = math.sqrt(minVSq) + 100 
                end

                local v2 = V * V
                local root = v2*v2 - G*(G*mDx*mDx + 2*mDy*v2)
                
                if root >= 0 then
                    local angleRad = math.atan((v2 + math.sqrt(root)) / (G * mDx))
                    local deg = math.deg(angleRad)
                    if deg >= 35 and deg <= 89.5 then 
                        return true, deg, mDx / (V * math.cos(angleRad)), mDx
                    end
                end
                return false, 45, 0, mDx
            end

            local vNear, gNear = 9070, 980 * 2.8   
            local vFar, gFar = 12520, 980 * 4.0    
            local vUltra, gUltra = 16800, 980 * 4.5 
            
            local isValid, physAngle, ToF, finalDx = false, 45, 0, 0
            
            local okNear, angNear, tofNear, dxN = CalcMortarTrajectory(vNear, gNear, targetPos.X, targetPos.Y, targetPos.Z)
            local okFar, angFar, tofFar, dxF = CalcMortarTrajectory(vFar, gFar, targetPos.X, targetPos.Y, targetPos.Z)
            local okUltra, angUltra, tofUltra, dxU = CalcMortarTrajectory(vUltra, gUltra, targetPos.X, targetPos.Y, targetPos.Z)

            if okNear and dxN <= 25000 then
                isValid, physAngle, ToF, finalDx = okNear, angNear, tofNear, dxN
            elseif okFar and dxF <= 40000 then
                isValid, physAngle, ToF, finalDx = okFar, angFar, tofFar, dxF
            elseif okUltra then
                isValid, physAngle, ToF, finalDx = okUltra, angUltra, tofUltra, dxU
            elseif okNear then
                isValid, physAngle, ToF, finalDx = okNear, angNear, tofNear, dxN
            end

            local targetCameraPitch = ((physAngle - 45) / 43.0) * 90.0 - 60.0
            local targetCameraYaw = rot.Yaw

            local deltaPitchMortar = targetCameraPitch - currentRot.Pitch
            local deltaYawMortar = targetCameraYaw - currentRot.Yaw

            if deltaPitchMortar > 180 then deltaPitchMortar = deltaPitchMortar - 360 end
            if deltaPitchMortar < -180 then deltaPitchMortar = deltaPitchMortar + 360 end
            if deltaYawMortar > 180 then deltaYawMortar = deltaYawMortar - 360 end
            if deltaYawMortar < -180 then deltaYawMortar = deltaYawMortar + 360 end
            
            finalPitch = currentRot.Pitch + (deltaPitchMortar * smoothFactor)
            finalYaw = currentRot.Yaw + (deltaYawMortar * smoothFactor)
        end

        local finalRot = { Pitch = finalPitch, Yaw = finalYaw, Roll = 0 }
        pc:SetControlRotation(finalRot, "AimTouch")
        
        if isShotgun and _G.ZEXYGODXConfig.AimTouchSGAutoFire then
            pcall(function()
                local distToTarget = player:GetDistanceTo(bestTarget) / 100
                if distToTarget <= maxDistMeters then
                    player.bIsWeaponFiring = true
                    if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(true) end
                    if slua.isValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(true) end
                    local wepMgr = player.WeaponManagerComponent
                    if slua.isValid(wepMgr) then wepMgr.bIsWeaponFiring = true end
                    
                    local currentWep = player:GetCurrentWeapon()
                    if slua.isValid(currentWep) and type(currentWep.StartFire) == "function" then 
                        currentWep:StartFire() 
                    end
                    _G.ZEXYGODXState.IsAutoFiring = true
                end
            end)
        end

    end)
end

-- ========================================== 
-- SISTEM SISTEM WALL & ESP ITEM ITEM/KENDARAAN KENDARAAN SANGAT HALUS (OPTIMIZED DI BAWAH 70M)
-- ========================================== 
local ItemDatabase = {
    -- AR
    [101001] = { name = "AKM", cat = "AR", color = {R=255,G=255,B=0,A=255} }, [101002] = { name = "M16A4", cat = "AR", color = {R=255,G=255,B=0,A=255} },
    [101003] = { name = "SCAR-L", cat = "AR", color = {R=255,G=255,B=0,A=255} }, [101004] = { name = "M416", cat = "AR", color = {R=255,G=255,B=0,A=255} },
    [101005] = { name = "Groza", cat = "AR", color = {R=255,G=255,B=0,A=255} }, [101006] = { name = "AUG", cat = "AR", color = {R=255,G=255,B=0,A=255} },
    [101008] = { name = "M762", cat = "AR", color = {R=255,G=255,B=0,A=255} },
    -- SMG
    [102001] = { name = "UZI", cat = "SMG", color = {R=0,G=255,B=255,A=255} }, [102002] = { name = "UMP45", cat = "SMG", color = {R=0,G=255,B=255,A=255} },
    [102003] = { name = "Vector", cat = "SMG", color = {R=0,G=255,B=255,A=255} }, [102004] = { name = "Thompson", cat = "SMG", color = {R=0,G=255,B=255,A=255} },
    -- Sniper
    [103001] = { name = "Kar98K", cat = "Sniper", color = {R=255,G=0,B=0,A=255} }, [103002] = { name = "M24", cat = "Sniper", color = {R=255,G=0,B=0,A=255} },
    [103003] = { name = "AWM", cat = "Sniper", color = {R=255,G=0,B=0,A=255} }, [103009] = { name = "SLR", cat = "Sniper", color = {R=255,G=0,B=0,A=255} },
    -- Shotgun
    [104001] = { name = "S686", cat = "Shotgun", color = {R=0,G=255,B=0,A=255} }, [104003] = { name = "S12K", cat = "Shotgun", color = {R=0,G=255,B=0,A=255} },
    [104004] = { name = "DBS", cat = "Shotgun", color = {R=0,G=255,B=0,A=255} }, 
    -- Senjata senapan (Gabungkan ke AR cho ringkas atau tampilkan selalu)
    [105001] = { name = "M249", cat = "AR", color = {R=255,G=255,B=255,A=255} }, [105002] = { name = "DP-28", cat = "AR", color = {R=255,G=255,B=255,A=255} }, 
    -- Scope
    [203004] = { name = "4x Scope", cat = "Scope", color = {R=0,G=0,B=255,A=255} }, [203005] = { name = "8x Scope", cat = "Scope", color = {R=0,G=0,B=255,A=255} }, 
    [203014] = { name = "3x Scope", cat = "Scope", color = {R=0,G=0,B=255,A=255} }, [203015] = { name = "6x Scope", cat = "Scope", color = {R=0,G=0,B=255,A=255} }
}

_G.CachedItems = {}
_G.LastScanItemTime = 0
_G.AppliedVehicleWall = {}
_G.AppliedItemESP = {}

-- ========================================== 
-- SISTEM SISTEM WALL & ESP ITEM ITEM/KENDARAAN KENDARAAN SANGAT HALUS (FULL 100% ASLI)
-- ========================================== 
local C_AR      = {R = 255, G = 255, B = 0, A = 255}
local C_SMG     = {R = 0, G = 255, B = 255, A = 255}
local C_Sniper  = {R = 255, G = 0, B = 0, A = 255}
local C_Shotgun = {R = 0, G = 255, B = 0, A = 255}
local C_LMG     = {R = 255, G = 255, B = 255, A = 255}
local C_Pistol  = {R = 200, G = 200, B = 200, A = 255}
local C_Special = {R = 255, G = 0, B = 255, A = 255}
local C_Melee   = {R = 150, G = 150, B = 150, A = 255}
local C_Scope   = {R = 0, G = 0, B = 255, A = 255}
local C_Grenade = {R = 255, G = 165, B = 0, A = 255}
local C_Med     = {R = 50, G = 255, B = 50, A = 255} -- Warna Xanh cho HP/Air

local ItemDatabase = {
    -- AR
    [101001] = { name = "AKM", cat = "AR", color = C_AR }, [101002] = { name = "M16A4", cat = "AR", color = C_AR },
    [101003] = { name = "SCAR-L", cat = "AR", color = C_AR }, [101004] = { name = "M416", cat = "AR", color = C_AR },
    [101005] = { name = "Groza", cat = "AR", color = C_AR }, [101006] = { name = "AUG", cat = "AR", color = C_AR },
    [101007] = { name = "QBZ", cat = "AR", color = C_AR }, [101008] = { name = "M762", cat = "AR", color = C_AR },
    [101009] = { name = "Mk47 Mutant", cat = "AR", color = C_AR }, [101010] = { name = "G36C", cat = "AR", color = C_AR },
    [101011] = { name = "AC-VAL", cat = "AR", color = C_AR }, [101012] = { name = "Honey Badger", cat = "AR", color = C_AR },
    [101100] = { name = "FAMAS", cat = "AR", color = C_AR }, [101101] = { name = "ASM Abakan AR", cat = "AR", color = C_AR },
    [101102] = { name = "ACE32", cat = "AR", color = C_AR },
    -- SMG
    [102001] = { name = "UZI", cat = "SMG", color = C_SMG }, [102002] = { name = "UMP45", cat = "SMG", color = C_SMG },
    [102003] = { name = "Vector", cat = "SMG", color = C_SMG }, [102004] = { name = "Thompson SMG", cat = "SMG", color = C_SMG },
    [102005] = { name = "PP-19 Bizon", cat = "SMG", color = C_SMG }, [102007] = { name = "MP5K", cat = "SMG", color = C_SMG },
    [102008] = { name = "JS9", cat = "SMG", color = C_SMG }, [102105] = { name = "P90", cat = "SMG", color = C_SMG },
    -- Sniper
    [103001] = { name = "Kar98K", cat = "Sniper", color = C_Sniper }, [103002] = { name = "M24", cat = "Sniper", color = C_Sniper },
    [103003] = { name = "AWM", cat = "Sniper", color = C_Sniper }, [103004] = { name = "SKS", cat = "Sniper", color = C_Sniper },
    [103005] = { name = "VSS", cat = "Sniper", color = C_Sniper }, [103006] = { name = "Mini14", cat = "Sniper", color = C_Sniper },
    [103007] = { name = "Mk14", cat = "Sniper", color = C_Sniper }, [103008] = { name = "Win94", cat = "Sniper", color = C_Sniper },
    [103009] = { name = "SLR", cat = "Sniper", color = C_Sniper }, [103010] = { name = "QBU", cat = "Sniper", color = C_Sniper },
    [103011] = { name = "Mosin Nagant", cat = "Sniper", color = C_Sniper }, [103012] = { name = "AMR", cat = "Sniper", color = C_Sniper },
    [103100] = { name = "Mk12", cat = "Sniper", color = C_Sniper }, [103101] = { name = "TR-2A Air Gun", cat = "Sniper", color = C_Sniper },
    [103102] = { name = "DSR", cat = "Sniper", color = C_Sniper }, [103103] = { name = "Sniper Rifle", cat = "Sniper", color = C_Sniper },
    [103104] = { name = "Sniper Rifle", cat = "Sniper", color = C_Sniper }, [103105] = { name = "SR", cat = "Sniper", color = C_Sniper },
    -- Shotgun
    [104001] = { name = "S686", cat = "Shotgun", color = C_Shotgun }, [104002] = { name = "S1897", cat = "Shotgun", color = C_Shotgun },
    [104003] = { name = "S12K", cat = "Shotgun", color = C_Shotgun }, [104004] = { name = "DBS", cat = "Shotgun", color = C_Shotgun },
    [104100] = { name = "SPAS-12", cat = "Shotgun", color = C_Shotgun }, [104101] = { name = "M1014", cat = "Shotgun", color = C_Shotgun },
    [104102] = { name = "NS2000", cat = "Shotgun", color = C_Shotgun },
    -- LMG
    [105001] = { name = "M249", cat = "LMG", color = C_LMG }, [105002] = { name = "DP-28", cat = "LMG", color = C_LMG },
    [105003] = { name = "M134", cat = "LMG", color = C_LMG }, [105010] = { name = "MG3", cat = "LMG", color = C_LMG },
    [105101] = { name = "Gatling", cat = "LMG", color = C_LMG }, [105115] = { name = "Lib Gatling MG", cat = "LMG", color = C_LMG },
    [105004] = { name = "Flamethrower", cat = "LMG", color = C_LMG }, [105006] = { name = "M2 Fixed MG", cat = "LMG", color = C_LMG },
    [105007] = { name = "Gatling Fixed MG", cat = "LMG", color = C_LMG }, [105008] = { name = "Mounted Flamethrower", cat = "LMG", color = C_LMG },
    [105009] = { name = "M2 Mounted MG", cat = "LMG", color = C_LMG }, [105102] = { name = "Vehicle SG", cat = "LMG", color = C_LMG },
    [105103] = { name = "RPG", cat = "LMG", color = C_LMG }, [105104] = { name = "RPG", cat = "LMG", color = C_LMG },
    [105105] = { name = "PowPow MG", cat = "LMG", color = C_LMG }, [105106] = { name = "Tank Cannon", cat = "LMG", color = C_LMG },
    [105107] = { name = "Tank MG", cat = "LMG", color = C_LMG }, [105108] = { name = "Tank Flare Gun", cat = "LMG", color = C_LMG },
    [105116] = { name = "Lib Autocannon", cat = "LMG", color = C_LMG }, [105117] = { name = "Jet Missile", cat = "LMG", color = C_LMG },
    [105118] = { name = "Jet Autocannon", cat = "LMG", color = C_LMG },
    -- Pistol & Flare terang
    [106001] = { name = "P92", cat = "Pistol", color = C_Pistol }, [106002] = { name = "P1911", cat = "Pistol", color = C_Pistol },
    [106003] = { name = "R1895", cat = "Pistol", color = C_Pistol }, [106004] = { name = "P18C", cat = "Pistol", color = C_Pistol },
    [106005] = { name = "R45", cat = "Pistol", color = C_Pistol }, [106006] = { name = "Sawed-off", cat = "Pistol", color = C_Pistol },
    [106008] = { name = "Skorpion", cat = "Pistol", color = C_Pistol }, [106010] = { name = "Desert Eagle", cat = "Pistol", color = C_Pistol },
    [106007] = { name = "Flare Gun", cat = "Pistol", color = C_Pistol }, [106009] = { name = "Flare Gun", cat = "Pistol", color = C_Pistol },
    [106011] = { name = "Dual MP7", cat = "Pistol", color = C_Pistol }, [106012] = { name = "Welding Gun", cat = "Pistol", color = C_Pistol },
    [106013] = { name = "Stun Gun", cat = "Pistol", color = C_Pistol }, [106101] = { name = "Vehicle Flare", cat = "Pistol", color = C_Pistol },
    [106103] = { name = "Flare Gun", cat = "Pistol", color = C_Pistol }, [106106] = { name = "Flare (Empty)", cat = "Pistol", color = C_Pistol },
    [106107] = { name = "Respawn Flare", cat = "Pistol", color = C_Pistol }, [106203] = { name = "Magnet Gun", cat = "Pistol", color = C_Pistol },
    -- Khusus khusus
    [107011] = { name = "Senjata Mortir", cat = "Special", color = C_Special }, [307006] = { name = "Peluru Mortir", cat = "Special", color = C_Special },
    [107001] = { name = "Crossbow", cat = "Special", color = C_Special }, [107002] = { name = "RPG-7", cat = "Special", color = C_Special },
    [107003] = { name = "Riot shield", cat = "Special", color = C_Special }, [107004] = { name = "Combat Drone", cat = "Special", color = C_Special },
    [107005] = { name = "Panzerfaust", cat = "Special", color = C_Special }, [107006] = { name = "RPG-7", cat = "Special", color = C_Special },
    [107007] = { name = "Tactical Crossbow", cat = "Special", color = C_Special }, [107008] = { name = "Explosive Bow", cat = "Special", color = C_Special },
    [107009] = { name = "Explosive Bow", cat = "Special", color = C_Special }, [107010] = { name = "M79 Smoke Launcher", cat = "Special", color = C_Special },
    [107019] = { name = "Atlas Gauntlet", cat = "Special", color = C_Special }, [107020] = { name = "Explosive Crossbow", cat = "Special", color = C_Special },
    [107021] = { name = "Mercury Hammer", cat = "Special", color = C_Special }, [107022] = { name = "Fishbones Rocket", cat = "Special", color = C_Special },
    [107031] = { name = "Summer Grenade Launcher", cat = "Special", color = C_Special }, [107032] = { name = "Summer Bazooka", cat = "Special", color = C_Special },
    [107033] = { name = "Summer MG", cat = "Special", color = C_Special }, [107034] = { name = "Color Bazooka", cat = "Special", color = C_Special },
    [107035] = { name = "Bubble MG", cat = "Special", color = C_Special }, [107036] = { name = "Snowball Blaster", cat = "Special", color = C_Special },
    [107037] = { name = "Water Orb Blaster", cat = "Special", color = C_Special }, [107092] = { name = "MGL", cat = "Special", color = C_Special },
    [107093] = { name = "M202 Quad RPG", cat = "Special", color = C_Special }, [107094] = { name = "AT4-A Laser Missile", cat = "Special", color = C_Special },
    [107095] = { name = "M202 Quad RPG", cat = "Special", color = C_Special }, [107096] = { name = "M79 Sawed-off", cat = "Special", color = C_Special },
    [107097] = { name = "M79", cat = "Special", color = C_Special }, [107098] = { name = "MGL", cat = "Special", color = C_Special },
    [107099] = { name = "M3E1-A", cat = "Special", color = C_Special }, [107901] = { name = "Zombie Piercer", cat = "Special", color = C_Special },
    [107903] = { name = "Mounted RPG", cat = "Special", color = C_Special }, [107904] = { name = "Helicopter RPG", cat = "Special", color = C_Special },
    [107911] = { name = "M3E1-B Missile", cat = "Special", color = C_Special },
    -- Jarak dekat
    [108001] = { name = "Machete", cat = "Melee", color = C_Melee }, [108002] = { name = "Crowbar", cat = "Melee", color = C_Melee },
    [108003] = { name = "Sickle", cat = "Melee", color = C_Melee }, [108004] = { name = "Pan", cat = "Melee", color = C_Melee },
    [108005] = { name = "Dagger", cat = "Melee", color = C_Melee }, [108006] = { name = "Mutation Blade", cat = "Melee", color = C_Melee },
    [108007] = { name = "Mutation Gauntlets", cat = "Melee", color = C_Melee },
    -- Scope
    [203001] = { name = "Red Dot Sight", cat = "Scope", color = C_Scope }, [203002] = { name = "Holographic Sight", cat = "Scope", color = C_Scope },
    [203003] = { name = "2x Scope", cat = "Scope", color = C_Scope }, [203004] = { name = "4x Scope", cat = "Scope", color = C_Scope },
    [203005] = { name = "8x Scope", cat = "Scope", color = C_Scope }, [203014] = { name = "3x Scope", cat = "Scope", color = C_Scope },
    [203015] = { name = "6x Scope", cat = "Scope", color = C_Scope },
    -- Granat peluru
    [602001] = { name = "Stun Grenade", cat = "Grenade", color = C_Grenade }, [602002] = { name = "Smoke Grenade", cat = "Grenade", color = C_Grenade },
    [602003] = { name = "Molotov", cat = "Grenade", color = C_Grenade }, [602004] = { name = "Frag Grenade", cat = "Grenade", color = C_Grenade },
    
    -- Item item Y medis (HP, Air, Pemulihan Pulihkan)
    [601001] = { name = "Air Tingkatkan Boost", cat = "Med", color = C_Med }, [601002] = { name = "Suntikan Adrenaline", cat = "Med", color = C_Med },
    [601003] = { name = "Obat Kurangi Nyeri", cat = "Med", color = C_Med }, [601004] = { name = "Perban Kasa", cat = "Med", color = C_Med },
    [601005] = { name = "Paket Pertolongan Medis", cat = "Med", color = C_Med }, [601006] = { name = "Paket Medis Kerusakan", cat = "Med", color = C_Med },
    [601009] = { name = "Perban Kasa Nhanh", cat = "Med", color = C_Med }, [601010] = { name = "Pertolongan Medis Nhanh", cat = "Med", color = C_Med },
    [601011] = { name = "Perban Kasa MILITER", cat = "Med", color = C_Med }, [601012] = { name = "Air Pekat Khusus", cat = "Med", color = C_Med },
    [601020] = { name = "Perban Kasa", cat = "Med", color = C_Med }, [601021] = { name = "Paket Pertolongan Medis", cat = "Med", color = C_Med },
    [601022] = { name = "Paket Medis Kerusakan", cat = "Med", color = C_Med }, [601023] = { name = "Suntikan Adrenaline", cat = "Med", color = C_Med },
    [601061] = { name = "Paket Medis Kerusakan", cat = "Med", color = C_Med }, [601077] = { name = "Pertolongan Medis Tempur Taktis", cat = "Med", color = C_Med },
    [601078] = { name = "Pertolongan Medis Semua Serbaguna", cat = "Med", color = C_Med }, [601079] = { name = "Medis Kerusakan Semua Serbaguna", cat = "Med", color = C_Med },
    [601080] = { name = "Perban Kasa MILITER", cat = "Med", color = C_Med }, [601081] = { name = "Air Pekat Khusus", cat = "Med", color = C_Med },
    [601084] = { name = "Pertolongan Medis Nhanh", cat = "Med", color = C_Med }, [601085] = { name = "Medis Kerusakan Nhanh", cat = "Med", color = C_Med },
    [601095] = { name = "Senapan AED (Pulihkan Sinh)", cat = "Med", color = C_Med }, [601096] = { name = "Siap Persiapan Tempur Pertarungan", cat = "Med", color = C_Med },
    [602054] = { name = "Lanjutan Medis Y Medis", cat = "Med", color = C_Med }, [602069] = { name = "Medis Bantuan Darurat Tingkat", cat = "Med", color = C_Med }
}

_G.CachedItems = {}
_G.LastScanItemTime = 0
_G.AppliedVehicleWall = {}
_G.AppliedItemESP = {}

_G.RunOptimizedItemAndVehicleESP = function(pc)
    local curTime = os.clock()

    -- 1. SCAN ACTOR DAN PROSES KELOLA ITEM KELOLA 1.0 DETIK / PERTAMA (Anti Drop FPS khi ambil barang)
    if curTime - _G.LastScanItemTime > 1.0 then
        _G.LastScanItemTime = curTime
        local player = GameplayData.GetPlayerCharacter()
        if not slua.isValid(player) then return end

        -- PROSES KELOLA WALL KENDARAAN KENDARAAN (Pertahankan asli jarak jarak lihat xa 200m)
        if _G.ZEXYGODXConfig.WallVehicle then
            local ASTExtraVehicleBase = import("STExtraVehicleBase")
            if ASTExtraVehicleBase then
                local Actors = Game:GetActorsByClass(ASTExtraVehicleBase)
                if Actors then
                    local count = Actors:Num() or 0
                    for i = 0, count - 1 do
                        local vehicle = Actors:Get(i)
                        if slua.isValid(vehicle) and vehicle.GetMesh then
                            local dist = player:GetDistanceTo(vehicle)
                            if dist <= 200000 then 
                                local vId = tostring(vehicle)
                                if not _G.AppliedVehicleWall[vId] then
                                    local mesh = vehicle:GetMesh()
                                    if slua.isValid(mesh) then
                                        local matInterface = mesh:GetMaterial(0)
                                        if slua.isValid(matInterface) then
                                            local baseMat = matInterface:GetBaseMaterial()
                                            if slua.isValid(baseMat) then
                                                baseMat.bDisableDepthTest = true
                                                baseMat.BlendMode = 2
                                                _G.AppliedVehicleWall[vId] = true
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        else _G.AppliedVehicleWall = {} end

        -- PROSES KELOLA ESP DAN CHAMS ITEM ITEM (Pelacak posisi teks & Glow bawah 70m)
        if _G.ZEXYGODXConfig.EspItem_Master then
            local APickUpWrapperActor = import("PickUpWrapperActor") or import("STPickupWrapperActor")
            if APickUpWrapperActor then
                local Actors = Game:GetActorsByClass(APickUpWrapperActor)
                _G.CachedItems = {}
                if Actors then
                    local count = Actors:Num() or 0
                    for i = 0, count - 1 do
                        local item = Actors:Get(i)
                        
                        -- [FIX MACET ITEM ITEM] Periksa tra xem item ada sedang tunggu terkena hapus tidak
                        local isPendingKill = false
                        pcall(function() if type(item.IsPendingKill) == "function" then isPendingKill = item:IsPendingKill() end end)

                        -- Hanya scan beberapa fisika item Valid Valid, Tidak Persiapan Sembunyikan (bHidden) dan Belum Persiapan Hapus
                        if slua.isValid(item) and not item.bHidden and not isPendingKill then
                            local dist = player:GetDistanceTo(item)
                            -- Batas batas 70m (7000 units), jamin jamin tidak hao CPU
                            if dist <= 7000 then
                                local itemId = item.DefineID and item.DefineID.TypeSpecificID or item.DefineId
                                local itemData = ItemDatabase[itemId]
                                
                                if itemData then
                                    -- Check xem fungsi saklar klasifikasi jenis ada sedang aktifkan tidak?
                                    local isShow = false
                                    if itemData.cat == "AR" and _G.ZEXYGODXConfig.EspItem_AR then isShow = true
                                    elseif itemData.cat == "Sniper" and _G.ZEXYGODXConfig.EspItem_Sniper then isShow = true
                                    elseif itemData.cat == "SMG" and _G.ZEXYGODXConfig.EspItem_SMG then isShow = true
                                    elseif itemData.cat == "Shotgun" and _G.ZEXYGODXConfig.EspItem_Shotgun then isShow = true
                                    elseif itemData.cat == "LMG" and _G.ZEXYGODXConfig.EspItem_LMG then isShow = true
                                    elseif itemData.cat == "Pistol" and _G.ZEXYGODXConfig.EspItem_Pistol then isShow = true
                                    elseif itemData.cat == "Melee" and _G.ZEXYGODXConfig.EspItem_Melee then isShow = true
                                    elseif itemData.cat == "Special" and _G.ZEXYGODXConfig.EspItem_Special then isShow = true
                                    elseif itemData.cat == "Grenade" and _G.ZEXYGODXConfig.EspItem_Grenade then isShow = true
                                    elseif itemData.cat == "Scope" and _G.ZEXYGODXConfig.EspItem_Scope then isShow = true
                                    elseif itemData.cat == "Med" and _G.ZEXYGODXConfig.EspItem_Med then isShow = true
                                    end

                                    -- Hanya proses fisika array dan gambar Glow jika sedang aktifkan
                                    if isShow then
                                        table.insert(_G.CachedItems, item)

                                        local iId = tostring(item)
                                        if not _G.AppliedItemESP[iId] then
                                            local meshes = {}
                                            if item.GetPickupMesh then
                                                local pMesh = item:GetPickupMesh()
                                                if slua.isValid(pMesh) then table.insert(meshes, pMesh) end
                                            end
                                            local childs = item:GetComponentsByClass(import("StaticMeshComponent"))
                                            if childs then
                                                for _, v in pairs(childs) do
                                                    if slua.isValid(v) then table.insert(meshes, v) end
                                                end
                                            end
                                            for _, mesh in pairs(meshes) do
                                                pcall(function() mesh:SetRenderCustomDepth(true) end)
                                                for mi = 0, 8 do
                                                    local mid = mesh:CreateAndSetMaterialInstanceDynamic(mi)
                                                    if slua.isValid(mid) then
                                                        local colorVisible = {R = 50, G = 50, B = 0, A = 10}
                                                        pcall(function()
                                                            mid:SetVectorParameterValue("LightColor", colorVisible)
                                                            mid:SetVectorParameterValue("ParaScaleOffset", {R = 3, G = 3, B = 0, A = 0})
                                                            mid:SetScalarParameterValue("RimLight", 999)
                                                            mid:SetScalarParameterValue("Brightness", 999)
                                                            mid:SetScalarParameterValue("Exposure", 999)
                                                        end)
                                                    end
                                                end
                                            end
                                            _G.AppliedItemESP[iId] = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        else 
            _G.AppliedItemESP = {}
            _G.CachedItems = {}
        end
    end

    -- 2. GAMBAR NAMA ITEM ITEM TERUS MENERUS KE KHUNG KONFIGURASI (Sangat ringan, gerak setiap frame)
    if _G.ZEXYGODXConfig.EspItem_Master and slua.isValid(pc) and pc.MyHUD then
        local hud = pc.MyHUD
        local player = GameplayData.GetPlayerCharacter()
        for _, item in ipairs(_G.CachedItems) do
            -- [MAKSIMAL OPTIMASI FPS MAKSIMAL MULTI] Hanya check bHidden (sangat ringan), abaikan qua pcall menghabiskan CPU di loop ulang setiap frame
            if slua.isValid(item) and not item.bHidden then
                local itemId = item.DefineID and item.DefineID.TypeSpecificID or item.DefineId
                if itemId and ItemDatabase[itemId] then
                    local itemData = ItemDatabase[itemId]
                    local dist = (player.GetDistanceTo and player:GetDistanceTo(item) or 0) / 100
                    local displayText = string.format("%s [%.0fm]", itemData.name, dist)
                    local textColor = {R = itemData.color.R, G = itemData.color.G, B = itemData.color.B, A = 255}
                    hud:AddDebugText(
                        displayText, item, 0.06, 
                        {X=0, Y=0, Z=50}, {X=0, Y=0, Z=50}, 
                        textColor, true, false, true, nil, 0.8, true
                    )
                end
            end
        end
    end
end


-- ========================================== 
-- UI WIDGET HITUNG MUSUH & JARAK JARAK DEKAT TERBANYAK (NEW ESP LOGIC)
-- ========================================== 
local BTN_BP = "/Game/UMG/UI_BP/Common/BaseComponent/CommonBaseComponent_TextButton_UIBP.CommonBaseComponent_TextButton_UIBP"
local EnemyCounterWidget = nil
local WarningTargetWidget = nil
local LastCounterTime = 0

-- TAMBAH FUNGSI BERSIHKAN BERSIHKAN WIDGET KHI KELUAR MATCH
function _G.CleanUpEnemyCounterWidget()
    if EnemyCounterWidget and slua.isValid(EnemyCounterWidget) then
        EnemyCounterWidget:RemoveFromParent()
    end
    EnemyCounterWidget = nil

    if WarningTargetWidget and slua.isValid(WarningTargetWidget) then
        WarningTargetWidget:RemoveFromParent()
    end
    WarningTargetWidget = nil
end

-- BUAT UI: HITUNG MUSUH (ASLI)
local function CreateEnemyCounterWidget()
    if EnemyCounterWidget then
        if slua.isValid(EnemyCounterWidget) then return EnemyCounterWidget else EnemyCounterWidget = nil end
    end

    pcall(function()
        local btn = slua.loadUI(BTN_BP)
        if not btn or not slua.isValid(btn) then return end
        require("game_frontend_hud").AddToContainer(UIContainers.Top, btn, 10500)
        
        if btn.RichText_Content then
            btn.RichText_Content:SetText("Musuh Musuh: 0  |  Dekat Terbaik: 0m")
            local fontInfo = btn.RichText_Content.Font
            if fontInfo then fontInfo.Size = 16 btn.RichText_Content:SetFont(fontInfo) end
        end
        
        local WidgetLayoutLibrary = import("WidgetLayoutLibrary")
        local slot = WidgetLayoutLibrary.SlotAsCanvasSlot(btn)
        if slot then
            slot:SetAnchors(FAnchors(0.5, 0, 0.5, 0))
            slot:SetAlignment(FVector2D(0.5, 0))
            slot:SetPosition(FVector2D(0, 30))
            slot:SetSize(FVector2D(240, 36))
        end
        btn:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        EnemyCounterWidget = btn
    end)
    return EnemyCounterWidget
end

-- BUAT UI: PERINGATAN PERINGATAN MUSUH BIDIK (UNIK MANDIRI)
local function CreateWarningTargetWidget()
    if WarningTargetWidget then
        if slua.isValid(WarningTargetWidget) then return WarningTargetWidget else WarningTargetWidget = nil end
    end

    pcall(function()
        local btn = slua.loadUI(BTN_BP)
        if not btn or not slua.isValid(btn) then return end
        require("game_frontend_hud").AddToContainer(UIContainers.Top, btn, 10501) -- Z-Order cao lebih untuk menonjol ke depan
        
        if btn.RichText_Content then
            -- Teks warna merah peringatan peringatan kuat
            btn.RichText_Content:SetText("MUSUH SEDANG LIHAT KE SISI ANDA")
            local fontInfo = btn.RichText_Content.Font
            if fontInfo then fontInfo.Size = 18 btn.RichText_Content:SetFont(fontInfo) end
        end
        
        local WidgetLayoutLibrary = import("WidgetLayoutLibrary")
        local slot = WidgetLayoutLibrary.SlotAsCanvasSlot(btn)
        if slot then
            slot:SetAnchors(FAnchors(0.5, 0, 0.5, 0))
            slot:SetAlignment(FVector2D(0.5, 0))
            slot:SetPosition(FVector2D(0, 75)) -- Terletak bagian bawah UI hitung musuh (Y=75)
            slot:SetSize(FVector2D(260, 36))
        end
        btn:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) -- Default tetapkan tersembunyi, hanya tampilkan khi terkena bidik
        WarningTargetWidget = btn
    end)
    return WarningTargetWidget
end

-- LOOP ULANG CHUNG (HITUNG HITUNG 1 PERTAMA CHO SEMUA 2 UI UNTUK ANTI DROP FPS)
local function _M_DrawCounter()
    if isExpired then
        _G.CleanUpEnemyCounterWidget()
        return
    end

    pcall(function()
        local player = GameplayData.GetPlayerCharacter()
        if not slua.isValid(player) then 
            if EnemyCounterWidget and slua.isValid(EnemyCounterWidget) then
                EnemyCounterWidget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end
            if WarningTargetWidget and slua.isValid(WarningTargetWidget) then
                WarningTargetWidget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end
            return 
        end

        local widgetCounter = CreateEnemyCounterWidget()
        local widgetWarning = CreateWarningTargetWidget()

        if widgetCounter and slua.isValid(widgetCounter) then
            widgetCounter:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end

        -- [MAKSIMAL OPTIMASI FPS] Kunci interval hitung hitung 0.5 detik / kali untuk hindari terlalu muat CPU
        local curTime = os.clock()
        if (curTime - LastCounterTime) > 0.5 then
            LastCounterTime = curTime
            
            local myTeam = player.TeamID or (type(player.GetTeamID) == "function" and player:GetTeamID()) or 0
            local count = 0
            local nearest = 9999
            local isBeingTargeted = false -- Status status peringatan peringatan
            
            local KismetMathLibrary = import("KismetMathLibrary")
            local pc = player:GetPlayerControllerSafety()

            local allCharacters = {}
            if GameplayData.GetAllPlayerCharacters then
                allCharacters = GameplayData.GetAllPlayerCharacters()
            elseif GameplayData.GameCharacters then
                for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end
            end

            for _, tPawn in pairs(allCharacters) do
                if slua.isValid(tPawn) and tPawn ~= player then
                    local isAlive = false
                    if tPawn.HealthStatus ~= nil then
                        isAlive = (tPawn.HealthStatus ~= 2)
                    else
                        isAlive = (tPawn.Health or 0) > 0 or (type(tPawn.IsAlive) == "function" and tPawn:IsAlive())
                    end
                    
                    if isAlive then
                        local tTeam = tPawn.TeamID or (type(tPawn.GetTeamID) == "function" and tPawn:GetTeamID()) or 0
                        if tTeam ~= myTeam then
                            count = count + 1
                            local d = math.floor(player:GetDistanceTo(tPawn) / 100)
                            if d < nearest then nearest = d end
                            
                            -- ========================================================
                            -- LOGIC CHECK MUSUH BIDIK (Hanya hitung khi jarak jarak < 400m)
                            -- ========================================================
                            if _G.ZEXYGODXConfig.EspAimWarning and not isBeingTargeted and d < 400 then
                                local eLoc = type(tPawn.K2_GetActorLocation) == "function" and tPawn:K2_GetActorLocation()
                                local pLoc = type(player.K2_GetActorLocation) == "function" and player:K2_GetActorLocation()
                                
                                if eLoc and pLoc and KismetMathLibrary then
                                    local lookRot = KismetMathLibrary.FindLookAtRotation(eLoc, pLoc)
                                    local eRot = nil
                                    
                                    if type(tPawn.GetControlRotation) == "function" then
                                        eRot = tPawn:GetControlRotation()
                                    elseif type(tPawn.GetActorRotation) == "function" then
                                        eRot = tPawn:GetActorRotation()
                                    end
                                    
                                    if eRot and lookRot then
                                        local dYaw = math.abs(eRot.Yaw - lookRot.Yaw)
                                        if dYaw > 180 then dYaw = 360 - dYaw end
                                        
                                        local dPitch = math.abs(eRot.Pitch - lookRot.Pitch)
                                        if dPitch > 180 then dPitch = 360 - dPitch end
                                        
                                        -- Musuh arah laras senjata sai selisih < 15 nilai
                                        if dYaw < 15 and dPitch < 20 then
                                            -- Terapkan menggunakan logic Check Dinding (VisCheck)
                                            if _G.ZEXYGODXConfig.EspAimWarningVisCheck then
                                                if slua.isValid(pc) and type(pc.LineOfSightTo) == "function" then
                                                    if pc:LineOfSightTo(tPawn) then
                                                        isBeingTargeted = true
                                                    end
                                                end
                                            else
                                                -- Tembus dinding peringatan selalu
                                                isBeingTargeted = true
                                            end
                                        end
                                    end
                                end
                            end
                            -- ========================================================
                        end
                    end
                end
            end

            -- Perbarui perbarui internal dung UI hitung musuh (Khung 1)
            if widgetCounter and widgetCounter.RichText_Content then
                widgetCounter.RichText_Content:SetText(string.format("@VENUSMOD2: %d  |  Dekat Terbaik: %dm", count, count > 0 and nearest or 0))
            end

            -- Sembunyikan/Tampilkan UI Peringatan peringatan unik simulasi (Khung 2)
            if widgetWarning and slua.isValid(widgetWarning) then
                if _G.ZEXYGODXConfig.EspAimWarning and isBeingTargeted then
                    widgetWarning:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                else
                    widgetWarning:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                end
            end
        end
    end)
end


-- ==========================================
-- LOOP FOV AIMBOT V2
-- ==========================================
_G.FovCircleOverlay = {
    Container = nil,
    WidgetSlot = nil,
    Lines = {},
    NumSegments = 45, -- [MAKSIMAL OPTIMASI] Kurangi dari 90 turun 45 (Kurangi 50% beban berat UI yang masih halus)
    Thickness = 1.5,  
    LastRadius = -1,
    LastColor = -1,
    LastCX = -1,
    LastCY = -1,
    PrecalcMath = nil -- [MAKSIMAL OPTIMASI] Paket ingat cache hitung belajar anti drop FPS
}

local function GetFOVColor(idx)
    if idx == 1 then return 1.0, 0.0, 0.0 end
    if idx == 2 then return 0.0, 1.0, 0.0 end
    if idx == 3 then return 0.0, 0.0, 1.0 end
    if idx == 4 then return 1.0, 1.0, 0.0 end
    if idx == 5 then return 0.65, 0.15, 1.0 end
    if idx == 6 then return 0.0, 1.0, 1.0 end
    if idx == 7 then return 1.0, 1.0, 1.0 end
    return 1.0, 1.0, 1.0 
end

function _G.FovCircleOverlay.Create()
    if _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then return true end
    
    local ParentCanvas = nil
    pcall(function()
        local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        local MainUI = InGameUITools.GetMainControlBaseUI()
        if slua.isValid(MainUI) then
            if slua.isValid(MainUI.CanvasPanel_0) then ParentCanvas = MainUI.CanvasPanel_0
            elseif slua.isValid(MainUI.CanvasPanel_42) then ParentCanvas = MainUI.CanvasPanel_42 end
        end
    end)
    
    if not ParentCanvas or not slua.isValid(ParentCanvas) then return false end

    local Container = nil
    pcall(function() Container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", ParentCanvas) end)
    if not Container or not slua.isValid(Container) then return false end

    local FVector2D = import("Vector2D") or _G.FVector2D
    
    for i = 1, _G.FovCircleOverlay.NumSegments do
        local border = nil
        pcall(function() border = CGame:NewObjectFromPath("/Script/UMG.Border", Container) end)
        if border and slua.isValid(border) then
            pcall(function() 
                border.RenderTransformPivot = FVector2D(0, 0.5)
                border:SetRenderTransformPivot(FVector2D(0, 0.5)) 
                border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
            local slot = Container:AddChildToCanvas(border)
            if slot then
                pcall(function() slot:SetAlignment(FVector2D(0, 0.5)) end)
            end
            _G.FovCircleOverlay.Lines[i] = { widget = border, slot = slot }
        end
    end

    local MainSlot = nil
    pcall(function() MainSlot = ParentCanvas:AddChildToCanvas(Container) end)
    if MainSlot then
        pcall(function()
            MainSlot:SetAutoSize(false)
            MainSlot:SetSize(FVector2D(0, 0))
            MainSlot:SetZOrder(995)
            MainSlot:SetAlignment(FVector2D(0, 0))
            MainSlot:SetPosition(FVector2D(0, 0))
        end)
    end
    _G.FovCircleOverlay.Container = Container
    _G.FovCircleOverlay.WidgetSlot = MainSlot
    return true
end

function _G.FovCircleOverlay.Update(pc, player)
    -- Hanya aksesori termasuk duy terbesar ke fungsi saklar "TAMPILKAN TAMPILAN LOOP FOV AIMBOT"
    if not _G.ZEXYGODXConfig.EspFovCircle then
        if _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
            pcall(function() _G.FovCircleOverlay.Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            _G.FovCircleOverlay.LastRadius = -1
        end
        return
    end

    local fovVal = 30
    local colIdx = 7 -- Default tetapkan adalah putih
    
    local cData = _G.ZEXYGODXState.CustomTextData
    local WEAPON_TYPE = _G.__AimTouch_WeaponType or "NORMAL"
    local isADS = player.bIsGunADS or false

    -- Baca Semi Scope FOV dan Warna Tajam Sesuai Responsif cho setiap jenis senjata
    if WEAPON_TYPE == "MORTAR" then
        fovVal = cData.AimTouchMortarFOV or 360
        colIdx = tonumber(cData.AimTouchMortarFOVColor) or 5
    elseif WEAPON_TYPE == "CROSSBOW" then
        fovVal = cData.AimTouchCrossbowFOV or 40
        colIdx = tonumber(cData.AimTouchSGFOVColor) or 1
    elseif WEAPON_TYPE == "BOW" then
        fovVal = cData.AimTouchBowFOV or 40
        colIdx = tonumber(cData.AimTouchSGFOVColor) or 1
    elseif WEAPON_TYPE == "SHOTGUN" then
        fovVal = cData.AimTouchSGFOV or 40
        colIdx = tonumber(cData.AimTouchSGFOVColor) or 1
    elseif isADS then
        if WEAPON_TYPE == "SNIPER" then
            fovVal = cData.AimTouchSniperFOV or 20
            colIdx = tonumber(cData.AimTouchSniperFOVColor) or 4
        else
            fovVal = cData.AimTouchScopeFOV or 30
            colIdx = tonumber(cData.AimTouchScopeFOVColor) or 6
        end
    else
        fovVal = cData.AimTouchHipFOV or 30
        colIdx = tonumber(cData.AimTouchHipFOVColor) or 7
    end

    local rawCX = _G.__AimTouch_CenterX or 960
    local rawCY = _G.__AimTouch_CenterY or 540
    local vpX = _G.__AimTouch_ViewportX or 1920

    local centerX = rawCX
    local centerY = rawCY
    local scaleX = 1.0

    -- [SOLUSI SOLUSI UNIK MANDIRI MAKSIMAL TINGGI] Otomatis bergerak hitung hitung khung outline, notch/tai kelinci dengan Engine milik Game (Tidak aksesori termasuk ke ESP V2)
    pcall(function()
        local parentCanvas = _G.FovCircleOverlay.Container:GetParent()
        if not slua.isValid(parentCanvas) then return end
        local cg = parentCanvas:GetCachedGeometry()
        if not cg then return end
        
        local SBL = import("SlateBlueprintLibrary") or import("/Script/UMG.SlateBlueprintLibrary")
        local WLL = import("WidgetLayoutLibrary") or import("/Script/UMG.WidgetLayoutLibrary")
        local FVector2D = import("Vector2D") or _G.FVector2D

        local success = false
        if SBL and SBL.AbsoluteToLocal then
            local pt0 = SBL.AbsoluteToLocal(cg, FVector2D(0, 0))
            local pt1 = SBL.AbsoluteToLocal(cg, FVector2D(100, 100))
            local centerPt = SBL.AbsoluteToLocal(cg, FVector2D(rawCX, rawCY))
            if pt0 and pt1 and centerPt then
                centerX = centerPt.X
                centerY = centerPt.Y
                scaleX = (pt1.X - pt0.X) / 100.0
                success = true
            end
        end

        if not success and WLL and WLL.ScreenToWidgetLocal then
            local pt0 = FVector2D(0, 0)
            local pt1 = FVector2D(0, 0)
            local centerPt = FVector2D(0, 0)
            WLL.ScreenToWidgetLocal(pc, cg, FVector2D(0, 0), pt0)
            WLL.ScreenToWidgetLocal(pc, cg, FVector2D(100, 100), pt1)
            WLL.ScreenToWidgetLocal(pc, cg, FVector2D(rawCX, rawCY), centerPt)
            
            centerX = centerPt.X
            centerY = centerPt.Y
            scaleX = (pt1.X - pt0.X) / 100.0
            success = true
        end
        
        if not success and WLL and WLL.GetViewportScale then
            local scale = WLL.GetViewportScale(pc)
            if scale and scale > 0 then
                scaleX = 1.0 / scale
                centerX = rawCX * scaleX
                centerY = rawCY * scaleX
            end
        end
    end)

    local rawRadius = (fovVal / 100.0) * (vpX / 2.0)
    local targetRadius = rawRadius * scaleX

    -- Jika anda nonaktifkan ESP membuat Game hapus lapisan gambar milik FOV -> Otomatis bergerak deteksi terlihat dan gambar lagi ngay simulasi yaitu
    if _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
        local parent = nil
        pcall(function() parent = _G.FovCircleOverlay.Container:GetParent() end)
        if not parent or not slua.isValid(parent) then
            _G.FovCircleOverlay.Container = nil
        end
    end

    if not _G.FovCircleOverlay.Create() then return end
    pcall(function() _G.FovCircleOverlay.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)

    -- [MAKSIMAL OPTIMASI 1] Tambahkan sai jumlah 0.5 pixel untuk hindari hancurkan pecah Cache terus menerus karena rung goyang layar konfigurasi
    if math.abs(_G.FovCircleOverlay.LastRadius - targetRadius) < 0.5 
       and _G.FovCircleOverlay.LastColor == colIdx 
       and math.abs(_G.FovCircleOverlay.LastCX - centerX) < 0.5 
       and math.abs(_G.FovCircleOverlay.LastCY - centerY) < 0.5 then
        return
    end

    _G.FovCircleOverlay.LastRadius = targetRadius
    _G.FovCircleOverlay.LastColor = colIdx
    _G.FovCircleOverlay.LastCX = centerX
    _G.FovCircleOverlay.LastCY = centerY

    local FLinearColor = import("LinearColor") or _G.FLinearColor
    local r, g, b = GetFOVColor(colIdx)
    local dim = 0.55 
    local color = FLinearColor and FLinearColor(r * dim, g * dim, b * dim, 1.0) or {R=r*dim*255, G=g*dim*255, B=b*dim*255, A=255}

    local numSegments = _G.FovCircleOverlay.NumSegments

    -- [MAKSIMAL OPTIMASI 2] Hitung hitung Sin/Cos siap 1 PERTAMA DUY TERBANYAK (Anti membebani CPU setiap khung konfigurasi)
    if not _G.FovCircleOverlay.PrecalcMath then
        _G.FovCircleOverlay.PrecalcMath = {}
        local angleStep = 360.0 / numSegments
        local math_cos = math.cos
        local math_sin = math.sin
        local math_rad = math.rad
        local math_atan2 = math.atan2 or math.atan
        
        for i = 1, numSegments do
            local angle1 = math_rad((i - 1) * angleStep)
            local angle2 = math_rad(i * angleStep)
            local c1, s1 = math_cos(angle1), math_sin(angle1)
            local c2, s2 = math_cos(angle2), math_sin(angle2)
            
            local dx_unit = c2 - c1
            local dy_unit = s2 - s1
            local dist_unit = math.sqrt(dx_unit*dx_unit + dy_unit*dy_unit)
            local angleDeg = math.deg(math_atan2(dy_unit, dx_unit))
            
            _G.FovCircleOverlay.PrecalcMath[i] = {
                c1 = c1, s1 = s1,
                dist_unit = dist_unit,
                angleDeg = angleDeg
            }
        end
    end

    pcall(function()
        local FVector2D = import("Vector2D") or _G.FVector2D
        for i = 1, numSegments do
            local mathData = _G.FovCircleOverlay.PrecalcMath[i]
            
            -- Hanya gunakan izin kali dasar versi sangat ringan thay karena hitung hitung jumlah deteksi kompleks rumit
            local x1 = targetRadius * mathData.c1
            local y1 = targetRadius * mathData.s1
            local dist = targetRadius * mathData.dist_unit

            local line = _G.FovCircleOverlay.Lines[i]
            if line and line.slot and slua.isValid(line.slot) then
                line.slot:SetPosition(FVector2D(centerX + x1, centerY + y1))
                line.slot:SetSize(FVector2D(dist + 0.8, _G.FovCircleOverlay.Thickness))
                line.widget:SetRenderAngle(mathData.angleDeg)
                line.widget:SetBrushColor(color)
            end
        end
    end)
end

function _G.CleanUpFovCircleOverlay()
    if _G.FovCircleOverlay and _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
        pcall(function() _G.FovCircleOverlay.Container:RemoveFromParent() end)
        pcall(function() _G.FovCircleOverlay.Container:ConditionalBeginDestroy() end)
    end
    if _G.FovCircleOverlay then
        _G.FovCircleOverlay.Container = nil
        _G.FovCircleOverlay.WidgetSlot = nil
        _G.FovCircleOverlay.LastRadius = -1
    end
end

-- ==========================================
-- SISTEM SISTEM TAMPILKAN TAMPILAN "DUNGCU" UNIK MANDIRI TOTAL BISA (KEAMANAN PROTEKSI ANTI ESP CLEAR)
-- ==========================================
local DungCuOverlay = {
    Widget = nil,
    Slot = nil
}

local function CleanUpPermanentDungCu()
    if DungCuOverlay.Widget and slua.isValid(DungCuOverlay.Widget) then
        pcall(function() DungCuOverlay.Widget:RemoveFromParent() end)
        pcall(function() DungCuOverlay.Widget:ConditionalBeginDestroy() end)
    end
    DungCuOverlay.Widget = nil
    DungCuOverlay.Slot = nil
end

local function EnsurePermanentDungCu()
    -- LANGKAH KEAMANAN PROTEKSI: Tanam perisai anti lagi mesin senapan bersihkan sampah milik ESP V2
    if _G.PlayerMapMarker and not _G.DungCu_Protected then
        local old_IsOurESPWidget = _G.PlayerMapMarker.IsOurESPWidget
        _G.PlayerMapMarker.IsOurESPWidget = function(w)
            -- Peringatan cho sistem sistem tahu ini TIDAK HARUS adalah sampah milik ESP, LARANG HAPUS!
            if DungCuOverlay.Widget and w == DungCuOverlay.Widget then 
                return false 
            end
            if _G.FovCircleOverlay and _G.FovCircleOverlay.Container and w == _G.FovCircleOverlay.Container then
                return false
            end
            if old_IsOurESPWidget then return old_IsOurESPWidget(w) end
            return false
        end
        _G.DungCu_Protected = true
    end

    -- 1. Jika teks sudah ada di layar konfigurasi, paksa mengikuti theo koordinat nilai unik simulasi selesai semua
    if DungCuOverlay.Widget and slua.isValid(DungCuOverlay.Widget) then 
        pcall(function() DungCuOverlay.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        pcall(function()
            if DungCuOverlay.Slot then
                local ui_util = require("client.common.ui_util")
                local vp = ui_util and ui_util.GetViewportSize()
                if vp then
                    local FVector2D = import("Vector2D") or _G.FVector2D
                    local targetX = vp.X * 0.5
                    local targetY = 42.0

                    local parentCanvas = DungCuOverlay.Widget:GetParent()
                    if slua.isValid(parentCanvas) then
                        local cg = parentCanvas:GetCachedGeometry()
                        local SBL = import("SlateBlueprintLibrary") or import("/Script/UMG.SlateBlueprintLibrary")
                        if cg and SBL and SBL.AbsoluteToLocal then
                            local centerPt = SBL.AbsoluteToLocal(cg, FVector2D(targetX, targetY))
                            if centerPt then
                                targetX = centerPt.X
                                targetY = centerPt.Y
                            end
                        end
                    end
                    DungCuOverlay.Slot:SetPosition(FVector2D(targetX, targetY))
                end
            end
        end)
        return 
    end

    -- 2. Jika belum ada, lanjut jalankan gambar baru
    local ParentCanvas = nil
    pcall(function()
        local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        local MainControlBaseUI = InGameUITools and InGameUITools.GetMainControlBaseUI()
        if MainControlBaseUI and slua.isValid(MainControlBaseUI) then
            ParentCanvas = MainControlBaseUI.CanvasPanel_0
            if not slua.isValid(ParentCanvas) then ParentCanvas = MainControlBaseUI.CanvasPanel_42 end
        end
    end)

    if not ParentCanvas or not slua.isValid(ParentCanvas) then return end

    local txtTitle = nil
    pcall(function() txtTitle = CGame:NewObjectFromPath("/Script/UMG.TextBlock", ParentCanvas) end)
    if txtTitle and slua.isValid(txtTitle) then
        pcall(function()
            txtTitle:SetText("VENUSFREEV14LITE")
            local FLinearColor = import("LinearColor") or _G.FLinearColor
            local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
            local redLinear = FLinearColor and FLinearColor(1.0, 0.0, 0.0, 1.0) or {R=255, G=0, B=0, A=255}
            if FSlateColor then txtTitle:SetColorAndOpacity(FSlateColor(redLinear)) else txtTitle:SetColorAndOpacity(redLinear) end

            if txtTitle.Font then
                local font = txtTitle.Font
                font.Size = 15
                txtTitle.Font = font
            end
            
            local FVector2D = import("Vector2D") or _G.FVector2D
            txtTitle:SetRenderScale(FVector2D(1.0, 1.0))
            txtTitle:SetRenderTransformPivot(FVector2D(0.5, 0.5))
            txtTitle:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)

        local txtSlot = ParentCanvas:AddChildToCanvas(txtTitle)
        if txtSlot then
            pcall(function()
                txtSlot:SetAutoSize(true)
                local FVector2D = import("Vector2D") or _G.FVector2D
                txtSlot:SetAlignment(FVector2D(0.5, 1.0))
                txtSlot:SetZOrder(9999)
            end)
            DungCuOverlay.Slot = txtSlot
        end
        DungCuOverlay.Widget = txtTitle
    end
end

-- ========================================== 
-- LOOP ULANG UTAMA (MAIN LOOP) MAKSIMAL OPTIMASI SANGAT KUAT
-- ========================================== 
local function MainLoop()
    if isExpired then return end

    

    if _G.ZEXYGODXState.CustomTextData == nil then 
        _G.ZEXYGODXState.CustomTextData = {OuterSpeed = 10, InnerSpeed = 10, HRecoil = 0.25, VRecoil = 0.25, MagicHead = 1.0, MagicBody = 1.0, MagicLegs = 1.0, IpadViewFOV = 120, IpadViewVehicleFOV = 120, IpadViewScopeFOV = 100, AimTouchHipPrio = 1, AimTouchHipBone = 1, AimTouchHipCond = 1, AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250, AimTouchSGPrio = 1, AimTouchSGBone = 2, AimTouchSGCond = 1, AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30, AimTouchScopePrio = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1, AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300, AimTouchSniperPrio = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2, AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400, FastCarSpeed = 2000}
    end

    local okData, GameplayData = pcall(require, "GameLua.GameCore.Data.GameplayData") 
    if not okData or not GameplayData then return end 
    local pc = GameplayData.GetPlayerController() 
    local localPlayer = nil
    if Valid(pc) then localPlayer = pc:GetPlayerCharacterSafety() end 

    -- HAPUS BERSIH BERSIH SANH SAMPAH DARI RAM KHI ANDA MATI, UBAH MAP, KE BERSIH (SUDAH FIX MEMORY LEAK)
    if not Valid(localPlayer) then 
        if _G.PlayerMapMarker and type(_G.PlayerMapMarker.Stop) == "function" then
            _G.PlayerMapMarker.Stop()
        end
        if _G.RedBoxOverlay and type(_G.RedBoxOverlay.Stop) == "function" then
            _G.RedBoxOverlay.Stop()
        end
        
        if _G.ZEXYGODXState.TrackedMarks then
            for markId, _ in pairs(_G.ZEXYGODXState.TrackedMarks) do SafeRemoveMark(markId) end
        end
        
        -- HAPUS TOTAL UNTUK PAKET INGAT CACHE MILIK SEMUA SEMUA BERBAGAI ESP (Anti crash game)
        _G.AppliedVehicleWall = {}
        _G.AppliedItemESP = {}
        _G.CachedItems = {}
        _G.CachedVehicles = {}
        _G.CachedActiveBombs = {}
        _G.CachedItemBombs = {}
        _G.AimTouchVisCache = {}
        _G.ActiveBombTimers = {}
        _G.BombCache = setmetatable({}, { __mode = "k" })
        _G.NonBombCache = setmetatable({}, { __mode = "k" })
        _G.AddOutfitLastAppliedSkin = {}
        
        _G.ZEXYGODXState.TrackedMarks = {} 
        for key, data in pairs(_G.ZEXYGODXState.EnemyMarks) do
            if data and data.MIDs then
                for meshStr, midTable in pairs(data.MIDs) do
                    for k, _ in pairs(midTable) do midTable[k] = nil end
                end
            end
            if data and data.MIDs_V3 then
                for meshStr, midTable in pairs(data.MIDs_V3) do
                    for k, _ in pairs(midTable) do midTable[k] = nil end
                end
            end
        end
        
        _G.ZEXYGODXState.EnemyMarks = {}
        _G.AK_OrigHitboxes = {}
        _G.AK_ModdedPhysAssets = {}
        _G.ZEXYGODXState.PrevGraphicsState = {}
        
        if _G.CleanUpEnemyCounterWidget then _G.CleanUpEnemyCounterWidget() end
        CleanUpPermanentDungCu() 
        if _G.CleanUpFovCircleOverlay then _G.CleanUpFovCircleOverlay() end
        return 
    end

    local Cached_PPM = nil
    pcall(function() Cached_PPM = import("PostProcessManager").GetInstance() end)
    local Cached_SecurityCommonUtils = nil
    pcall(function() Cached_SecurityCommonUtils = require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils") end)
    local Cached_MyHUD = pc and pc.MyHUD or nil

    if _G.ZEXYGODXConfig.UnlockFPS then InitializeGraphicsUnlock() end
    InitializeNativeESP()
    ShowZEXYGODXVIPMenu()

    -- [PANGGIL LOGIC DUNGCU] Selalu gerak unik simulasi tidak perlu fungsi saklar
    EnsurePermanentDungCu()
    
    -- [PANGGIL LOGIC ESP ITEM DAN VEHICLE KE LOOP ULANG]
    if _G.ZEXYGODXConfig.WallVehicle or _G.ZEXYGODXConfig.EspItem_Master then
        _G.RunOptimizedItemAndVehicleESP(pc)
    end
    
    -- [INTEGRASI GABUNG] LOGIC AKTIFKAN/MATIKAN ESP JENIS 9 KE MAINLOOP (TIDAK GUNAKAN TIMER MENYEBABKAN LAG)
    if _G.ZEXYGODXConfig.EspLoai9 then
        if _G.PlayerMapMarker then
            if not _G.PlayerMapMarker.bActive then _G.PlayerMapMarker.Start() end
            
            local curTime = os.clock()
            -- Scan direktori target 0.5s/Kali (Ringan senapan)
            if not _G.LastEsp9Scan or (curTime - _G.LastEsp9Scan) > 0.5 then
                _G.LastEsp9Scan = curTime
                pcall(function() _G.PlayerMapMarker.ScanAndUpdate() end)
            end
            
            -- Perbarui perbarui jarak jarak 0.1s/Kali
            if not _G.LastEsp9Dist or (curTime - _G.LastEsp9Dist) > 0.1 then
                _G.LastEsp9Dist = curTime
                pcall(function() _G.PlayerMapMarker.UpdateESPDistances() end)
            end
            
            -- Perbarui perbarui posisi posisi gambar ESP theo khung konfigurasi (Halus Tru)
            pcall(function() _G.PlayerMapMarker.UpdateESPLight() end)
        end
    else
        if _G.PlayerMapMarker and _G.PlayerMapMarker.bActive then
            _G.PlayerMapMarker.Stop()
        end
    end
    
    -- LOGIC IPAD VIEW (JALAN PAKET, MENGEMUDI XE DAN BUKA SCOPE) SUDAH TINGKATKAN LEVEL
    pcall(function()
        local isAiming = false
        if localPlayer.bIsWeaponAiming or localPlayer.bIsGunADS then isAiming = true end

        local currentVehicle = localPlayer.CurrentVehicle or (type(localPlayer.GetVehicle) == "function" and localPlayer:GetVehicle())
        local isInVehicle = Valid(currentVehicle) or localPlayer.bIsInVehicle
        local uTPPCam = localPlayer.ThirdPersonCameraComponent
        local uVehCam = localPlayer.VehicleCameraComponent
        local camMgr = pc.PlayerCameraManager

        -- 1. PROSES KELOLA KHI SEDANG BUKA SCOPE (BIDIK TEMBAK)
        if isAiming then
            if _G.ZEXYGODXConfig.IpadViewScope and _G.ZEXYGODXState.CustomTextData then
                local targetScope = _G.ZEXYGODXState.CustomTextData.IpadViewScopeFOV or 60
                if type(pc.FOV) == "function" then pc:FOV(targetScope) end
                if Valid(camMgr) then
                    camMgr.DefaultFOV = targetScope
                    if type(camMgr.SetFOV) == "function" then camMgr:SetFOV(targetScope) end
                end
            else
                -- Jika nonaktifkan Ipad Scope, kembalikan lagi FOV sebenarnya milik Game untuk bidik standar
                if type(pc.FOV) == "function" then pc:FOV(0) end
                if Valid(camMgr) and type(camMgr.UnlockFOV) == "function" then camMgr:UnlockFOV() end
            end
            return -- Hentikan logic pergi lokal/xe karena prioritas prioritas Scope
        end

        -- 2. PROSES KELOLA KHI TIDAK BIDIK TEMBAK (JALAN PAKET ATAU MENGEMUDI XE)
        -- Pemulihan pulihkan camera jika sebelumnya itu baru saja nonaktifkan Scope
        if not isInVehicle or not _G.ZEXYGODXConfig.IpadViewVehicle then
            if type(pc.FOV) == "function" then pc:FOV(0) end
            if Valid(camMgr) and type(camMgr.UnlockFOV) == "function" then camMgr:UnlockFOV() end
        end

        -- Pergi Paket
        if not isInVehicle then
            if _G.ZEXYGODXConfig.IpadView and _G.ZEXYGODXState.CustomTextData then
                local targetTPP = _G.ZEXYGODXState.CustomTextData.IpadViewFOV or 120
                if Valid(uTPPCam) and uTPPCam.FieldOfView ~= targetTPP then 
                    uTPPCam.FieldOfView = targetTPP 
                end
            else
                if Valid(uTPPCam) and uTPPCam.FieldOfView ~= 90 then 
                    uTPPCam.FieldOfView = 90 
                end
            end
        end

        -- Mengemudi Xe
        if isInVehicle then
            if _G.ZEXYGODXConfig.IpadViewVehicle and _G.ZEXYGODXState.CustomTextData then
                local targetVeh = _G.ZEXYGODXState.CustomTextData.IpadViewVehicleFOV or 120
                
                if Valid(uVehCam) and uVehCam.FieldOfView ~= targetVeh then 
                    uVehCam.FieldOfView = targetVeh 
                end
                
                if targetVeh > 90 then
                    if type(pc.FOV) == "function" then pc:FOV(targetVeh) end
                    if Valid(camMgr) then
                        camMgr.DefaultFOV = targetVeh
                        if type(camMgr.SetFOV) == "function" then camMgr:SetFOV(targetVeh) end
                    end
                end
            else
                if Valid(uVehCam) and uVehCam.FieldOfView ~= 90 then 
                    uVehCam.FieldOfView = 90 
                end
            end
        end
    end)

    -- ========================================================
    -- LOGIC AIMBOT V2 ROYAL/CUSTOM DAN LOOP FOV
    -- ========================================================
    pcall(function()
        local ui_util = require("client.common.ui_util")
        if ui_util then
            local vp = ui_util.GetViewportSize()
            if vp then
                _G.__AimTouch_ViewportX = vp.X
                _G.__AimTouch_CenterX = vp.X * 0.5
                _G.__AimTouch_CenterY = vp.Y * 0.5
            end
        end
        
        local wName = ""
        local weapon = localPlayer.WeaponManagerComponent and localPlayer.WeaponManagerComponent.CurrentWeaponReplicated
        if not weapon and type(localPlayer.GetCurrentShootWeapon) == "function" then
            weapon = localPlayer:GetCurrentShootWeapon()
        end
        if slua.isValid(weapon) then
            wName = type(weapon.GetWeaponName) == "function" and weapon:GetWeaponName() or ""
            local wID = type(weapon.GetWeaponID) == "function" and weapon:GetWeaponID() or 0
            if (wID >= 1030000 and wID < 1040000) or wName:find("S686") or wName:find("S1897") or wName:find("S12") or wName:find("DBS") or wName:find("M1014") then 
                _G.__AimTouch_WeaponType = "SHOTGUN"
            elseif wName:find("Kar98") or wName:find("M24") or wName:find("AWM") or wName:find("Mosin") or wName:find("Win94") or wName:find("AMR") or wName:find("SKS") or wName:find("SLR") or wName:find("Mini") or wName:find("Mk14") or wName:find("QBU") or wName:find("Mk12") or wName:find("VSS") then
                _G.__AimTouch_WeaponType = "SNIPER"
            elseif wName:lower():find("mortar") or wName:lower():find("cối") then
                _G.__AimTouch_WeaponType = "MORTAR"
            elseif wName:lower():find("crossbow") or wName:lower():find("panah") then
                _G.__AimTouch_WeaponType = "CROSSBOW"
            elseif wName:lower():find("bow") or wName:lower():find("cung") then
                _G.__AimTouch_WeaponType = "BOW"
            else
                _G.__AimTouch_WeaponType = "NORMAL"
            end
        end
    end)

    if _G.ZEXYGODXConfig.AimTouchEnable then
        _G.AimTouch()
    end

    if _G.FovCircleOverlay then
        pcall(function() _G.FovCircleOverlay.Update(pc, localPlayer) end)
    end
    
    -- [TAMBAH BARU] LOGIC GLOW SENJATA (UNIK MANDIRI & SANGAT HALUS 0.5s/Kali - JAMIN KEAMANAN 0% DROP FPS)
    if not _G.LastGlowTime or (os.clock() - _G.LastGlowTime) > 0.5 then
        _G.LastGlowTime = os.clock()
        if _G.ApplyWeaponGlow then _G.ApplyWeaponGlow(localPlayer) end
    end

    
    
    

    -- SEPENUHNYA KEMBALIKAN GRAFIS GRAFIS NGAY MANDIRI SEGERA JIKA MATIKAN (MATIKAN ADALAH MATIKAN LANGSUNG)
    local now = os.clock()
    pcall(function()
        local lsg = require("client.slua.logic.setting.logic_setting_graphics")
        local gi = lsg.GetGameInstance()
        if gi then
            if _G.ZEXYGODXConfig.RemoveGrass and not _G.ZEXYGODXState.PrevGraphicsState.RemoveGrass then
                gi:ExecuteCMD("grass.DensityScale", "0")
                gi:ExecuteCMD("grass.DiscardDataOnLoad", "1")
                _G.ZEXYGODXState.PrevGraphicsState.RemoveGrass = true
            elseif not _G.ZEXYGODXConfig.RemoveGrass and _G.ZEXYGODXState.PrevGraphicsState.RemoveGrass then
                gi:ExecuteCMD("grass.DensityScale", "1")
                gi:ExecuteCMD("grass.DiscardDataOnLoad", "0")
                _G.ZEXYGODXState.PrevGraphicsState.RemoveGrass = false
            end

            -- LOGIC HAPUS POHON
            if _G.ZEXYGODXConfig.RemoveTrees and not _G.ZEXYGODXState.PrevGraphicsState.RemoveTrees then
                gi:ExecuteCMD("foliage.DensityScale", "0")
                gi:ExecuteCMD("r.Foliage.DensityScale", "0")
                gi:ExecuteCMD("foliage.MinimumScreenSize", "10000")
                gi:ExecuteCMD("r.DisableTreeRender", "1")
                _G.ZEXYGODXState.PrevGraphicsState.RemoveTrees = true
            elseif not _G.ZEXYGODXConfig.RemoveTrees and _G.ZEXYGODXState.PrevGraphicsState.RemoveTrees then
                gi:ExecuteCMD("foliage.DensityScale", "1")
                gi:ExecuteCMD("r.Foliage.DensityScale", "1")
                gi:ExecuteCMD("foliage.MinimumScreenSize", "0.0001")
                gi:ExecuteCMD("r.DisableTreeRender", "0")
                _G.ZEXYGODXState.PrevGraphicsState.RemoveTrees = false
            end
            
            if _G.ZEXYGODXConfig.RemoveFog and not _G.ZEXYGODXState.PrevGraphicsState.RemoveFog then
                gi:ExecuteCMD("r.SkyAtmosphere", "1") 
                gi:ExecuteCMD("r.Fog", "0")           
                gi:ExecuteCMD("r.VolumetricFog", "0") 
                _G.ZEXYGODXState.PrevGraphicsState.RemoveFog = true
            elseif not _G.ZEXYGODXConfig.RemoveFog and _G.ZEXYGODXState.PrevGraphicsState.RemoveFog then
                gi:ExecuteCMD("r.SkyAtmosphere", "1") 
                gi:ExecuteCMD("r.Fog", "1")           
                gi:ExecuteCMD("r.VolumetricFog", "1") 
                _G.ZEXYGODXState.PrevGraphicsState.RemoveFog = false
            end
            
            if _G.ZEXYGODXConfig.WhiteBody and not _G.ZEXYGODXState.PrevGraphicsState.WhiteBody then
                gi:ExecuteCMD("r.CharacterDiffuseOffset", "2")
                gi:ExecuteCMD("r.CharacterDiffusePower", "5")
                gi:ExecuteCMD("r.CharacterMinShadowFactor", "100")
                _G.ZEXYGODXState.PrevGraphicsState.WhiteBody = true
            elseif not _G.ZEXYGODXConfig.WhiteBody and _G.ZEXYGODXState.PrevGraphicsState.WhiteBody then
                gi:ExecuteCMD("r.CharacterDiffuseOffset", "0")
                gi:ExecuteCMD("r.CharacterDiffusePower", "1")
                gi:ExecuteCMD("r.CharacterMinShadowFactor", "1")
                _G.ZEXYGODXState.PrevGraphicsState.WhiteBody = false
            end
            
            if _G.ZEXYGODXConfig.ColorBodyV2 and not _G.ZEXYGODXState.PrevGraphicsState.ColorBodyV2 then
                gi:ExecuteCMD("r.CharacterMinShadowFactor", "4")
                gi:ExecuteCMD("r.CharacterDiffuseOffset", "200")
                gi:ExecuteCMD("r.CharacterDiffusePower", "200")
                _G.ZEXYGODXState.PrevGraphicsState.ColorBodyV2 = true
            elseif not _G.ZEXYGODXConfig.ColorBodyV2 and _G.ZEXYGODXState.PrevGraphicsState.ColorBodyV2 then
                gi:ExecuteCMD("r.CharacterMinShadowFactor", "1")
                gi:ExecuteCMD("r.CharacterDiffuseOffset", "0")
                gi:ExecuteCMD("r.CharacterDiffusePower", "1")
                _G.ZEXYGODXState.PrevGraphicsState.ColorBodyV2 = false
            end
            
            -- LOGIC BLACKSKY
            if _G.ZEXYGODXConfig.BlackSky and not _G.ZEXYGODXState.PrevGraphicsState.BlackSky then
                gi:ExecuteCMD("r.CylinderMaxDrawHeight", "9999")
                _G.ZEXYGODXState.PrevGraphicsState.BlackSky = true
            elseif not _G.ZEXYGODXConfig.BlackSky and _G.ZEXYGODXState.PrevGraphicsState.BlackSky then
                gi:ExecuteCMD("r.CylinderMaxDrawHeight", "0000")
                _G.ZEXYGODXState.PrevGraphicsState.BlackSky = false
            end
        end
    end)

    pcall(function()
        local weapon = nil
        pcall(function()
            local weaponManager = localPlayer.WeaponManagerComponent
            if Valid(weaponManager) and type(weaponManager.GetCurrentWeapon) == "function" then
                weapon = weaponManager:GetCurrentWeapon()
            end
        end)
        if not Valid(weapon) then
            if type(localPlayer.GetCurrentShootWeapon) == "function" then weapon = localPlayer:GetCurrentShootWeapon()
            elseif type(localPlayer.GetCurrentWeapon) == "function" then weapon = localPlayer:GetCurrentWeapon() end
        end

        if Valid(weapon) then
            local entities = {}
            if Valid(weapon.ShootWeaponEntity_GEN_VARIABLE) then table.insert(entities, weapon.ShootWeaponEntity_GEN_VARIABLE) end
            if Valid(weapon.ShootWeaponEntity) then table.insert(entities, weapon.ShootWeaponEntity) end
            if Valid(weapon.ShootWeaponComponent) and Valid(weapon.ShootWeaponComponent.ShootWeaponEntityComponent) then 
                table.insert(entities, weapon.ShootWeaponComponent.ShootWeaponEntityComponent) 
            end

            for _, entity in ipairs(entities) do
                local anyWeaponModOn = _G.ZEXYGODXConfig.CustomHRecoil or _G.ZEXYGODXConfig.CustomVRecoil or _G.ZEXYGODXConfig.LessShake or _G.ZEXYGODXConfig.Accuracy or _G.ZEXYGODXConfig.Crosshair or _G.ZEXYGODXConfig.GodMode or _G.ZEXYGODXConfig.AutoHead or _G.ZEXYGODXConfig.CustomAimbot or _G.ZEXYGODXConfig.CustomAimbotClose or _G.ZEXYGODXConfig.AimbotMode ~= "None" or _G.ZEXYGODXConfig.LessRecoil or _G.ZEXYGODXConfig.VerticalRecoil

                if anyWeaponModOn then
                    if not entity.OriginalStatsCached then
                        entity.OriginalStatsCached = {
                            GameDeviationFactor = entity.GameDeviationFactor,
                            GameDeviationAccuracy = entity.GameDeviationAccuracy,
                            BulletFireSpeed = entity.BulletFireSpeed,
                            ShootInterval = entity.ShootInterval,
                            BaseDamage = entity.BaseDamage,
                            AccessoriesHRecoilFactor = entity.AccessoriesHRecoilFactor,
                            AccessoriesVRecoilFactor = entity.AccessoriesVRecoilFactor,
                            RecoilKick = entity.RecoilKick,
                            RecoilKickADS = entity.RecoilKickADS,
                            AnimationKick = entity.AnimationKick
                        }
                    end
                    
                    if _G.ZEXYGODXConfig.CustomHRecoil then entity.AccessoriesHRecoilFactor = _G.ZEXYGODXState.CustomTextData.HRecoil or 0.25 
                    elseif _G.ZEXYGODXConfig.LessRecoil then entity.AccessoriesHRecoilFactor = 0.25 end
                    
                    if _G.ZEXYGODXConfig.CustomVRecoil then entity.AccessoriesVRecoilFactor = _G.ZEXYGODXState.CustomTextData.VRecoil or 0.25
                    elseif _G.ZEXYGODXConfig.VerticalRecoil then entity.AccessoriesVRecoilFactor = 0.25 end
                    
                    if _G.ZEXYGODXConfig.LessShake then entity.RecoilKick = 0.0; entity.RecoilKickADS = 0.0; entity.AnimationKick = 0.0 end
                    if _G.ZEXYGODXConfig.Accuracy then entity.GameDeviationAccuracy = 0.0 end
                    if _G.ZEXYGODXConfig.Crosshair then entity.GameDeviationFactor = 0.0 end
                    if _G.ZEXYGODXConfig.GodMode then entity.BulletFireSpeed = 500000.0; entity.ShootInterval = 0.001; entity.BaseDamage = 60000.0 end
                    
                    if entity.AutoAimingConfig then
                        if not entity.OriginalAutoAimCached then
                            entity.OriginalAutoAimCached = {
                                OuterSpeed = entity.AutoAimingConfig.OuterRange and entity.AutoAimingConfig.OuterRange.Speed,
                                InnerSpeed = entity.AutoAimingConfig.InnerRange and entity.AutoAimingConfig.InnerRange.Speed
                            }
                        end
                        
                        if _G.ZEXYGODXConfig.AutoHead then
                            pcall(function() entity.AutoAimingConfig.Bones = { "Head", "Head", "Head" } end)
                        end
                        
                        if _G.ZEXYGODXConfig.CustomAimbot then
                            local speed = _G.ZEXYGODXState.CustomTextData.OuterSpeed or 10
                            if entity.AutoAimingConfig.OuterRange then
                                entity.AutoAimingConfig.OuterRange.Speed = speed
                                entity.AutoAimingConfig.OuterRange.RangeRate = 4.5
                                entity.AutoAimingConfig.OuterRange.SpeedRate = 1.3
                                entity.AutoAimingConfig.OuterRange.RangeRateSight = 1.8
                                entity.AutoAimingConfig.OuterRange.SpeedRateSight = 2.2
                                entity.AutoAimingConfig.OuterRange.CrouchRate = 1.1
                                entity.AutoAimingConfig.OuterRange.ProneRate = 1.0
                                entity.AutoAimingConfig.OuterRange.DyingRate = 0.0
                            end
                            if entity.AutoAimingConfig.InnerRange then
                                entity.AutoAimingConfig.InnerRange.Speed = speed
                                entity.AutoAimingConfig.InnerRange.RangeRate = 4.5
                                entity.AutoAimingConfig.InnerRange.SpeedRate = 1.3
                                entity.AutoAimingConfig.InnerRange.RangeRateSight = 1.8
                                entity.AutoAimingConfig.InnerRange.SpeedRateSight = 2.2
                                entity.AutoAimingConfig.InnerRange.CrouchRate = 1.1
                                entity.AutoAimingConfig.InnerRange.ProneRate = 1.0
                                entity.AutoAimingConfig.InnerRange.DyingRate = 0.0
                            end
                        elseif _G.ZEXYGODXConfig.CustomAimbotClose or _G.ZEXYGODXConfig.AimbotMode == "Close" then
                            local speed = _G.ZEXYGODXState.CustomTextData.InnerSpeed or 10
                            if entity.AutoAimingConfig.OuterRange then
                                entity.AutoAimingConfig.OuterRange.Speed = speed
                                entity.AutoAimingConfig.OuterRange.DyingRate = 0.0
                            end
                            if entity.AutoAimingConfig.InnerRange then
                                entity.AutoAimingConfig.InnerRange.Speed = speed
                                entity.AutoAimingConfig.InnerRange.DyingRate = 0.0
                            end
                        elseif _G.ZEXYGODXConfig.AimbotMode == "Far" then
                            if entity.AutoAimingConfig.OuterRange then
                                entity.AutoAimingConfig.OuterRange.Speed = 5
                                entity.AutoAimingConfig.OuterRange.RangeRate = 0.7
                                entity.AutoAimingConfig.OuterRange.SpeedRate = 1.3
                                entity.AutoAimingConfig.OuterRange.RangeRateSight = 1.8
                                entity.AutoAimingConfig.OuterRange.SpeedRateSight = 2.2
                                entity.AutoAimingConfig.OuterRange.CrouchRate = 1.1
                                entity.AutoAimingConfig.OuterRange.ProneRate = 1
                            end
                            if entity.AutoAimingConfig.InnerRange then
                                entity.AutoAimingConfig.InnerRange.Speed = 5
                                entity.AutoAimingConfig.InnerRange.RangeRate = 0.7
                                entity.AutoAimingConfig.InnerRange.SpeedRate = 1.3
                                entity.AutoAimingConfig.InnerRange.RangeRateSight = 1.8
                                entity.AutoAimingConfig.InnerRange.SpeedRateSight = 2.2
                                entity.AutoAimingConfig.InnerRange.CrouchRate = 1.1
                                entity.AutoAimingConfig.InnerRange.ProneRate = 1
                            end
                        end
                    end
                    
                    entity.ZEXYGODXWeaponModsActive = true

                elseif entity.ZEXYGODXWeaponModsActive then
                    if entity.OriginalStatsCached then
                        local orig = entity.OriginalStatsCached
                        entity.GameDeviationFactor = orig.GameDeviationFactor
                        entity.GameDeviationAccuracy = orig.GameDeviationAccuracy
                        entity.BulletFireSpeed = orig.BulletFireSpeed
                        entity.ShootInterval = orig.ShootInterval
                        entity.BaseDamage = orig.BaseDamage
                        entity.AccessoriesHRecoilFactor = orig.AccessoriesHRecoilFactor
                        entity.AccessoriesVRecoilFactor = orig.AccessoriesVRecoilFactor
                        entity.RecoilKick = orig.RecoilKick
                        entity.RecoilKickADS = orig.RecoilKickADS
                        entity.AnimationKick = orig.AnimationKick
                    end
                    if entity.AutoAimingConfig and entity.OriginalAutoAimCached then
                        pcall(function() entity.AutoAimingConfig.Bones = { "Spine_01", "Pelvis", "Head" } end)
                        if entity.AutoAimingConfig.OuterRange and entity.OriginalAutoAimCached.OuterSpeed then
                            entity.AutoAimingConfig.OuterRange.Speed = entity.OriginalAutoAimCached.OuterSpeed
                        end
                        if entity.AutoAimingConfig.InnerRange and entity.OriginalAutoAimCached.InnerSpeed then
                            entity.AutoAimingConfig.InnerRange.Speed = entity.OriginalAutoAimCached.InnerSpeed
                        end
                    end
                    entity.ZEXYGODXWeaponModsActive = false
                end
            end
        end
    end)

    local mHead_Global, mBody_Global, mLegs_Global = 1.0, 1.0, 1.0
    local runInject_Global = false
    
    pcall(function()
        if _G.ZEXYGODXConfig.CustomMagicBullet then
            runInject_Global = true
            mHead_Global = 1.0; mBody_Global = 1.0; mLegs_Global = 1.0
            if _G.ZEXYGODXState.CustomTextData then
                local cData = _G.ZEXYGODXState.CustomTextData
                if cData.MagicHead ~= nil then mHead_Global = tonumber(cData.MagicHead) or mHead_Global end
                if cData.MagicBody ~= nil then mBody_Global = tonumber(cData.MagicBody) or mBody_Global end
                if cData.MagicLegs ~= nil then mLegs_Global = tonumber(cData.MagicLegs) or mLegs_Global end
            end
        elseif _G.ZEXYGODXConfig.MagicBullet then
            runInject_Global = true
            mHead_Global = 1.05; mBody_Global = 1.0; mLegs_Global = 1.0
        end

        if runInject_Global then
            local currentMagicHash = "M_"..tostring(mHead_Global).."_"..tostring(mBody_Global).."_"..tostring(mLegs_Global)
            if _G.ZEXYGODXState.LastMagicConfigHash ~= currentMagicHash then
                _G.ZEXYGODXState.MagicUpdateVersion = (_G.ZEXYGODXState.MagicUpdateVersion or 0) + 1
                _G.ZEXYGODXState.LastMagicConfigHash = currentMagicHash
            end
        else
            -- KHI MAGIC BULLET TERKENA MATIKAN, RESTORE LAGI HASH KE 0
            if _G.ZEXYGODXState.LastMagicConfigHash ~= "OFF" then
                _G.ZEXYGODXState.MagicUpdateVersion = (_G.ZEXYGODXState.MagicUpdateVersion or 0) + 1
                _G.ZEXYGODXState.LastMagicConfigHash = "OFF"
            end
        end
    end)

    pcall(function()
        local allCharacters = {}
        if GameplayData.GetAllPlayerCharacters then allCharacters = GameplayData.GetAllPlayerCharacters()
        elseif GameplayData.GameCharacters then for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end end
        
        local currentValidKeys = {}
        for _, enemy in pairs(allCharacters) do
            if Valid(enemy) and enemy ~= localPlayer then
                currentValidKeys[GetSafeEnemyKey(enemy)] = true
            end
        end
        
        for key, data in pairs(_G.ZEXYGODXState.EnemyMarks) do
            if not currentValidKeys[key] then
                SafeRemoveMark(data.radarMark)
                SafeRemoveMark(data.hpMark)
                SafeRemoveMark(data.distMark)
                
                -- [FIX RAM]: Bersihkan sampah AimTouch VisCheck milik musuh sudah mati atau crash terlalu xa
                if _G.AimTouchVisCache and _G.AimTouchVisCache[key] then
                    _G.AimTouchVisCache[key] = nil
                end
                
                if data.MIDs then
                    for meshStr, midTable in pairs(data.MIDs) do
                        for k, _ in pairs(midTable) do
                            midTable[k] = nil
                        end
                    end
                    data.MIDs = nil
                end
                if data.MIDs_V3 then
                    for meshStr, midTable in pairs(data.MIDs_V3) do
                        for k, _ in pairs(midTable) do
                            midTable[k] = nil
                        end
                    end
                    data.MIDs_V3 = nil
                end
                
                data.enemy = nil
                data.CachedMeshes = nil
                _G.ZEXYGODXState.EnemyMarks[key] = nil
            end
        end

        local realCount = 0
        local aiCount = 0

        local function GetFirstElemSafe(elemArray)
            if elemArray and type(elemArray.Num) == "function" and elemArray:Num() > 0 then
                if type(elemArray.Get) == "function" then return elemArray:Get(0) end
            elseif elemArray and type(elemArray) == "table" and #elemArray > 0 then
                return elemArray[1]
            end
            return nil
        end

        local BoneScaleMap = {
            ["head"] = mHead_Global, ["neck_01"] = mHead_Global,
            ["pelvis"] = mBody_Global, ["spine_01"] = mBody_Global, ["spine_02"] = mBody_Global, ["spine_03"] = mBody_Global,
            ["thigh_l"] = mLegs_Global, ["thigh_r"] = mLegs_Global, 
            ["calf_l"] = mLegs_Global, ["calf_r"] = mLegs_Global,   
            ["foot_l"] = mLegs_Global, ["foot_r"] = mLegs_Global    
        }
        
        local mLoc = nil
        pcall(function() if type(localPlayer.K2_GetActorLocation) == "function" then mLoc = localPlayer:K2_GetActorLocation() end end)

        for _, enemy in pairs(allCharacters) do
            if Valid(enemy) and enemy ~= localPlayer and enemy.TeamID ~= localPlayer.TeamID then
                local bIsReallyDead = false
                pcall(function()
                    if type(enemy.IsDead) == "function" then bIsReallyDead = enemy:IsDead()
                    elseif enemy.bIsDead ~= nil then bIsReallyDead = enemy.bIsDead
                    elseif enemy.bIsDeadFlag ~= nil then bIsReallyDead = enemy.bIsDeadFlag end
                    if enemy.HealthStatus ~= nil and enemy.HealthStatus == 2 then bIsReallyDead = true end
                end)

                local eKey = GetSafeEnemyKey(enemy)
                _G.ZEXYGODXState.EnemyMarks[eKey] = _G.ZEXYGODXState.EnemyMarks[eKey] or { enemy = enemy }
                local markData = _G.ZEXYGODXState.EnemyMarks[eKey]
                markData.enemy = enemy 

                if not bIsReallyDead then
                    -- [FIX ERROR HILANG HP KHI LOMPAT PARASUT/PULIHKAN SINH]: Periksa tra xem musuh ada terkena ubah Actor (kali fisika baru) tidak.
                    -- Jika ada, hapus semua lokal Marker (UI) terkena macet di mayat lama untuk code bagian bawah gambar lagi ke depan kali fisika baru.
                    if markData.lastEnemyActor ~= enemy then
                        if markData.hpMark then SafeRemoveMark(markData.hpMark); markData.hpMark = nil end
                        if markData.hpMark8 then SafeRemoveMark(markData.hpMark8); markData.hpMark8 = nil end -- Hapus selalu sampah milik ESP 8
                        if markData.distMark then SafeRemoveMark(markData.distMark); markData.distMark = nil end
                        if markData.radarMark then SafeRemoveMark(markData.radarMark); markData.radarMark = nil end
                        
                        markData.lastEnemyActor = enemy
                        markData.LastUIComp = nil
                        markData.LastFrameUIState = nil
                    end
                    
                    local eMesh = nil
                    pcall(function() eMesh = enemy.Mesh or (type(enemy.getAvatarComponent2) == "function" and enemy:getAvatarComponent2() or nil) end)
                    local aLoc = nil
                    pcall(function() if type(enemy.K2_GetActorLocation) == "function" then aLoc = enemy:K2_GetActorLocation() end end)
                    
                    local isBotResult, isStateLoaded = CheckIsAI(enemy, markData)
                    local isBot = markData.AK_IS_BOT or false

                    local currentMeshCount = 0
                    if Valid(eMesh) then
                        local tempMeshes = GetAllSkeletalMeshes(enemy, markData)
                        currentMeshCount = #tempMeshes
                    end
                    local isMeshChanged = (markData.LastMeshCountWall ~= currentMeshCount)

                    -- SUDAH MAKSIMAL OPTIMASI SANGAT PERIODE: Hanya Apply khi sebenarnya perubahan perlu
                    if _G.ZEXYGODXConfig.WallXuyenTuong then
                        if isMeshChanged or not markData.WallhackApplied then
                            ApplyWallXuyenTuong(enemy, markData)
                            markData.WallhackApplied = true
                            markData.LastMeshCountWall = currentMeshCount
                        end
                    else
                        UndoWallXuyenTuong(enemy, markData)
                    end

                    -- SUDAH MAKSIMAL OPTIMASI SANGAT PERIODE
                    if _G.ZEXYGODXConfig.ColorBodyV2 then 
                        -- TRONG FUNGSI INI SAYA SUDAH BATAS BATAS PC:LINEOFSIGHTTO LAGI UNTUK HINDARI TERLALU MUAT CPU
                        ApplyColorBodyV2(enemy, pc, markData) 
                    else
                        UndoColorBodyV2(enemy, markData)
                    end
                    
                    -- FITUR FITUR WARNA V3 (TERLIHAT TAMPILAN XANH DAUN + SAU DINDING WARNA MERAH) SANGAT STABIL STABIL
                    if _G.ZEXYGODXConfig.ColorBodyV3 then 
                        ApplyColorBodyV3(enemy, markData)
                    else
                        UndoColorBodyV3(enemy, markData)
                    end
                    -- FITUR FITUR WALL WARNA NEW
                    if _G.ZEXYGODXConfig.ColorBodyNew then 
                        ApplyColorBodyNew(enemy, markData)
                    else
                        UndoColorBodyNew(enemy, markData)
                    end

                    -- BUG LAYAR: TARIK RENGGANG MUSUH MUSUH DIBUAT HITBOX TO RA (FAT BODY) - SUDAH MAKSIMAL OPTIMASI
                    pcall(function()
                        if Valid(eMesh) then
                            local targetScale = 1.0
                            if _G.ZEXYGODXConfig.BugManEnable and _G.ZEXYGODXState.CustomTextData then
                                targetScale = 177.0 / (_G.ZEXYGODXState.CustomTextData.BugManRatio or 133)
                                if targetScale < 1.0 then targetScale = 1.0 end
                                if targetScale > 2.0 then targetScale = 2.0 end -- Anti error barang grafis jika geser terlalu tingkat
                            end
                            
                            -- [FIX SAMPAH RAM]: Hanya renggang tulang khi ada perubahan thay ubah (Aktifkan/nonaktifkan atau geser thanh geser)
                            if markData.LastFatScale ~= targetScale then
                                eMesh:SetRelativeScale3D(FVector(targetScale, targetScale, 1.0))
                                markData.LastFatScale = targetScale
                            end
                        end
                    end)

                    -- LOGIC MAGIC BULLET (SUDAH FIX LAG RAMAI PEMAIN DENGAN UNIQUE ID)
                    pcall(function()
                        local EnemyMesh = eMesh
                        if slua.isValid(EnemyMesh) then
                            -- [FIX CPU SANGAT KUAT]: Gunakan ID sebenarnya milik kali fisika. Tidak gunakan tostring() karena SLUA otomatis hapus/buat lagi string terus menerus
                            -- menyebabkan error hitung hitung lagi 50 khung tulang ulang pergi ulang lagi khi ramai pemain.
                            local uniqueID = type(enemy.GetUniqueID) == "function" and enemy:GetUniqueID() or tostring(enemy.PlayerKey or enemy)
                            
                            -- Hanya hitung hitung tulang BENAR 1 PERTAMA DUY TERBANYAK cho setiap musuh musuh (kurangi khi anda geser thanh atur size)
                            if markData.MagicBulletHash == _G.ZEXYGODXState.LastMagicConfigHash and markData.MagicTargetID == uniqueID then
                                return 
                            end

                            local PhysicsAsset = EnemyMesh.PhysicsAssetOverride
                            if not slua.isValid(PhysicsAsset) and EnemyMesh.SkeletalMesh then PhysicsAsset = EnemyMesh.SkeletalMesh.PhysicsAsset end

                            if slua.isValid(PhysicsAsset) and PhysicsAsset.SkeletalBodySetups then
                                if not _G.AK_ModdedPhysAssets then _G.AK_ModdedPhysAssets = {} end
                                local PhysAssetName = "DefaultPhys"
                                pcall(function() PhysAssetName = PhysicsAsset:GetName() end)
                                
                                -- Maksimal prioritas tingkat 2: Jika lokal tulang ini sudah setiap dapat zoom to oleh satu musuh musuh lain, gunakan selalu, tidak gerak loop ulang
                                if _G.AK_ModdedPhysAssets[PhysAssetName] ~= _G.ZEXYGODXState.LastMagicConfigHash then
                                    
                                    if not _G.AK_OrigHitboxes then _G.AK_OrigHitboxes = {} end
                                    if not _G.AK_OrigHitboxes[PhysAssetName] then _G.AK_OrigHitboxes[PhysAssetName] = {} end
                                    local OrigHitboxData = _G.AK_OrigHitboxes[PhysAssetName]

                                    local SkeletalBodySetups = PhysicsAsset.SkeletalBodySetups
                                    local numSetups = type(SkeletalBodySetups.Num) == "function" and SkeletalBodySetups:Num() or #SkeletalBodySetups
                                    local limit = numSetups > 50 and 50 or numSetups

                                    for i = 1, limit do 
                                        local BodySetup = type(SkeletalBodySetups.Get) == "function" and SkeletalBodySetups:Get(i-1) or SkeletalBodySetups[i]
                                        if slua.isValid(BodySetup) then
                                            local LowerBoneName = string.lower(tostring(BodySetup.BoneName))
                                            local MatchedBoneKey = nil
                                            for k, _ in pairs(BoneScaleMap) do
                                                if string.find(LowerBoneName, k, 1, true) then MatchedBoneKey = k break end
                                            end

                                            if MatchedBoneKey then
                                                local TargetScale = 1.0 
                                                if runInject_Global then TargetScale = BoneScaleMap[MatchedBoneKey] end
                                                
                                                local AggGeom = BodySetup.AggGeom
                                                
                                                local BoxElems = AggGeom and AggGeom.BoxElems or BodySetup.BoxElems
                                                local SphereElems = AggGeom and AggGeom.SphereElems or BodySetup.SphereElems
                                                local SphylElems = AggGeom and AggGeom.SphylElems or BodySetup.SphylElems

                                                local BoxElem = GetFirstElemSafe(BoxElems)
                                                local SphereElem = GetFirstElemSafe(SphereElems)
                                                local SphylElem = GetFirstElemSafe(SphylElems)

                                                if not OrigHitboxData[MatchedBoneKey] then
                                                    OrigHitboxData[MatchedBoneKey] = { Box = nil, Sphere = nil, Sphyl = nil }
                                                    if BoxElem then OrigHitboxData[MatchedBoneKey].Box = { X = BoxElem.X, Y = BoxElem.Y, Z = BoxElem.Z } end
                                                    if SphereElem then OrigHitboxData[MatchedBoneKey].Sphere = { Radius = SphereElem.Radius } end
                                                    if SphylElem then OrigHitboxData[MatchedBoneKey].Sphyl = { Radius = SphylElem.Radius, Length = SphylElem.Length } end
                                                end

                                                local OrigElemData = OrigHitboxData[MatchedBoneKey]

                                                if OrigElemData.Box and BoxElem then
                                                    BoxElem.X = OrigElemData.Box.X * TargetScale
                                                    BoxElem.Y = OrigElemData.Box.Y * TargetScale
                                                    BoxElem.Z = OrigElemData.Box.Z * TargetScale
                                                    if type(BoxElems.Set) == "function" then BoxElems:Set(0, BoxElem) else BoxElems[1] = BoxElem end
                                                    if AggGeom then AggGeom.BoxElems = BoxElems; BodySetup.AggGeom = AggGeom else BodySetup.BoxElems = BoxElems end
                                                end

                                                if OrigElemData.Sphere and SphereElem then
                                                    SphereElem.Radius = OrigElemData.Sphere.Radius * TargetScale
                                                    if type(SphereElems.Set) == "function" then SphereElems:Set(0, SphereElem) else SphereElems[1] = SphereElem end
                                                    if AggGeom then AggGeom.SphereElems = SphereElems; BodySetup.AggGeom = AggGeom else BodySetup.SphereElems = SphereElems end
                                                end

                                                if OrigElemData.Sphyl and SphylElem then
                                                    SphylElem.Radius = OrigElemData.Sphyl.Radius * TargetScale
                                                    SphylElem.Length = OrigElemData.Sphyl.Length * TargetScale
                                                    if type(SphylElems.Set) == "function" then SphylElems:Set(0, SphylElem) else SphylElems[1] = SphylElem end
                                                    if AggGeom then AggGeom.SphylElems = SphylElems; BodySetup.AggGeom = AggGeom else BodySetup.SphylElems = SphylElems end
                                                end
                                            end
                                        end
                                    end
                                    _G.AK_ModdedPhysAssets[PhysAssetName] = _G.ZEXYGODXState.LastMagicConfigHash
                                end
                                
                                if EnemyMesh.SetPhysicsAsset then EnemyMesh:SetPhysicsAsset(PhysicsAsset) end
                                EnemyMesh.PhysicsAssetOverride = PhysicsAsset
                                
                                markData.MagicBulletHash = _G.ZEXYGODXState.LastMagicConfigHash
                                markData.MagicTargetID = uniqueID -- Simpan ID statis
                            end
                        end
                    end)

                    local distM = 0
                    pcall(function() distM = localPlayer:GetDistanceTo(enemy) / 100 end)

                    local currentHp, maxHp = 100, 100
                    local showFrameUI = _G.ZEXYGODXConfig.EspLoai5 or _G.ZEXYGODXConfig.EspVipPro or _G.ZEXYGODXConfig.EspVip
                    
                    if showFrameUI then
                        pcall(function()
                            if enemy.Health then currentHp = enemy.Health elseif type(enemy.GetHealth) == "function" then currentHp = enemy:GetHealth() end
                            if enemy.HealthMax then maxHp = enemy.HealthMax elseif type(enemy.GetHealthMax) == "function" then maxHp = enemy:GetHealthMax() end
                        end)
                        if maxHp <= 0 then maxHp = 100 end
                    end
                    local hpRatio = currentHp / maxHp

                    if _G.ZEXYGODXConfig.EspAntenna then
                        pcall(function()
                            local MyHUD = Cached_MyHUD
                            if Valid(MyHUD) and distM <= 400 then
                                local loopCount = 8  
                                local zStep = 1000     
                                local baseZ = 105     
                                local topZ = baseZ + (loopCount * zStep)
                                for i = 1, loopCount do
                                    local zOffset = baseZ + (i * zStep)
                                    MyHUD:AddDebugText("|", enemy, 0.06,
                                        {X=0, Y=0, Z=zOffset}, {X=0, Y=0, Z=zOffset},
                                        C_GREEN, true, false, true, nil, 1.2, true)
                                end
                                MyHUD:AddDebugText("I", enemy, 0.06,
                                        {X=0, Y=0, Z=topZ + 60}, {X=0, Y=0, Z=topZ + 60},
                                        C_GREEN, true, false, true, nil, 1.5, true)
                            end
                        end)
                    end

                    if _G.ZEXYGODXConfig.EspLoai6 then
                        pcall(function()
                            local curTime = os.clock()
                            -- MAKSIMAL OPTIMASI SANGAT TINGKAT 1: Kunci interval gambar HUD 20 FPS (0.05s/kali) thay karena 100 FPS
                            -- Game masih halus, tetapi CPU tidak terkena membebani karena spam perintah AddDebugText
                            if markData.LastEsp6Time == nil or (curTime - markData.LastEsp6Time) >= 0.05 then
                                markData.LastEsp6Time = curTime
                                
                                local MyHUD = Cached_MyHUD
                                if Valid(MyHUD) and Valid(eMesh) and aLoc then
                                    if distM <= 250 then
                                        -- Ambil koordinat nilai Kepala prioritas menentukan, jika tidak ada fungsi ini maka abaikan qua
                                        if type(eMesh.GetSocketLocation) == "function" then
                                            for _, bName in ipairs(GLOBAL_BONE_LIST) do
                                                
                                                -- MAKSIMAL OPTIMASI SANGAT TINGKAT 2: Musuh xa lebih 50m hanya gambar Kepala, Leher, Pinggul. Abaikan qua tay kaki bantuan sampah
                                                if distM > 50 and (bName ~= "head" and bName ~= "pelvis" and bName ~= "neck_01") then
                                                    -- Skip tidak gambar tay kaki di xa
                                                else
                                                    local wLoc = eMesh:GetSocketLocation(bName)
                                                    if wLoc then
                                                        -- Hitung Offset standar cho HUD
                                                        local offset = {X = wLoc.X - aLoc.X, Y = wLoc.Y - aLoc.Y, Z = wLoc.Z - aLoc.Z}
                                                        
                                                        local mark = "▪"
                                                        local fixedSize = 0.25 
                                                        local color = C_CYAN
                                                        
                                                        if bName == "head" then 
                                                            mark = "●"
                                                            fixedSize = 0.45
                                                            color = C_RED
                                                        elseif bName == "pelvis" or bName == "neck_01" then 
                                                            mark = "▪"
                                                            fixedSize = 0.35
                                                            color = C_YELLOW 
                                                        end
                                                        
                                                        -- Gambar titik neo milik sambungan tulang (Waktu gian hidup 0.06s untuk hubungkan halus dengan frame 0.05s)
                                                        MyHUD:AddDebugText(mark, enemy, 0.06, offset, offset, color, true, false, true, nil, fixedSize, true)
                                                    end
                                                end
                                            end
                                        end
                                        -- SIMPAN SETUJU: SUDAH HAPUS HAPUS SEPENUHNYA TOTAL HITUNG FITUR GAMBAR GARIS PENGHUBUNG (GLOBAL_CONNECTIONS)
                                        -- Karena gunakan tanda titik "." susun menjadi garis adalah asli kali utama menyebabkan drop FPS 
                                    end
                                end
                            end
                        end)
                    end

                    if _G.ZEXYGODXConfig.EspLoai7 then
                        pcall(function()
                            local MyHUD = Cached_MyHUD
                            if Valid(MyHUD) then
                                if distM <= 600 then if isBot then aiCount = aiCount + 1 else realCount = realCount + 1 end end
                                
                                if distM <= 400 then
                                    local stateText = ""
                                    
                                    

                                    -- 3. Gambar ke depan layar konfigurasi jika ada aktifkan 1 trong 2
                                    if stateText ~= "" then
                                        local textColor = isBot and C_CYAN or C_YELLOW
                                        local dynamicScale = math.max(0.5, 0.8 - (distM / 400))
                                        MyHUD:AddDebugText(stateText, enemy, 0.06, {X=0, Y=0, Z=100}, {X=0, Y=0, Z=100}, textColor, true, false, true, nil, dynamicScale, true)
                                    end
                                end
                            end
                        end)
                    end

                    -- SUDAH MAKSIMAL OPTIMASI SANGAT PERIODE: Hanya SetVisibility cho UI khung hp khi sebenarnya perubahan perlu
                    if showFrameUI then
                        pcall(function()
                            local SecurityCommonUtils = Cached_SecurityCommonUtils
                            local show = true
                            if enemy.HealthStatus and SecurityCommonUtils and SecurityCommonUtils.IsHealthStatusAlive then 
                                if not SecurityCommonUtils.IsHealthStatusAlive(enemy.HealthStatus) then show = false end
                            end
                            if show and mLoc then
                                if aLoc and SecurityCommonUtils and SecurityCommonUtils.IsVector then
                                    if SecurityCommonUtils.IsVector(aLoc) and SecurityCommonUtils.IsVector(mLoc) then
                                        if aLoc.Z >= 150000 or FVector.Dist2D(mLoc, aLoc) > 50000 then show = false end
                                    end
                                end
                            end
                            if show then
                                if enemy.Replay_IsEnemyFrameUIExisted and not enemy:Replay_IsEnemyFrameUIExisted() then enemy:Replay_CreateEnemyFrameUI(true, true) end
                                if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(true) end
                                if enemy.Replay_UpdateEnemyFrameUI then enemy:Replay_UpdateEnemyFrameUI(hpRatio) end
                                
                                local uiComp = enemy.EnemyFrameUI or (type(enemy.GetEnemyFrameUI) == "function" and enemy:GetEnemyFrameUI())
                                if Valid(uiComp) then
                                    if markData.LastFrameUIState ~= "VISIBLE" then
                                        if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(0) end
                                        if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(false) end
                                        markData.LastFrameUIState = "VISIBLE"
                                    end
                                end
                            end
                        end)
                    else
                        pcall(function()
                            if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(false) end
                            local uiComp = enemy.EnemyFrameUI or (type(enemy.GetEnemyFrameUI) == "function" and enemy:GetEnemyFrameUI())
                            if Valid(uiComp) then
                                if markData.LastFrameUIState ~= "HIDDEN" then
                                    if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(2) end
                                    if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(true) end
                                    markData.LastFrameUIState = "HIDDEN"
                                end
                            end
                        end)
                    end

                    if _G.ZEXYGODXConfig.EspVipPro then
                        pcall(function()
                            local hud = Cached_MyHUD
                            if Valid(hud) and hud.AddDebugText then
                                if distM <= 400 then
                                    local dynamicScale = math.max(0.55, 0.95 - (distM / 400))
                                    local hpPercent = hpRatio
                                    local isKnock = (currentHp <= 0 and enemy.HealthStatus == 1)
                                    
                                    local hpColor = C_GREEN
                                    if hpPercent < 0.3 then hpColor = C_RED
                                    elseif hpPercent < 0.7 then hpColor = C_YELLOW end
                                    if isKnock then hpColor = C_RED end
                                    
                                    -- GAMBAR NAMA PEMAIN MAIN
                                    if _G.ZEXYGODXConfig.Esp3ShowName then
                                        local enemyName = "Enemy"
                                        pcall(function() if enemy.PlayerName then enemyName = enemy.PlayerName elseif type(enemy.GetPlayerName) == "function" then enemyName = enemy:GetPlayerName() end end)
                                        if enemyName == "" then enemyName = "Enemy" end
                                        if isKnock then enemyName = "KNOCK: " .. enemyName end
                                        hud:AddDebugText(enemyName, enemy, 0.06, {X=0, Y=0, Z=-370}, {X=0, Y=0, Z=-370}, C_WHITE, true, false, true, nil, dynamicScale * 1.1, true)
                                    end
                                    
                                    -- GAMBAR THANH HP
                                    if _G.ZEXYGODXConfig.Esp3ShowHP then
                                        if not isKnock then
                                            local segments = 6
                                            local filled = math.floor(hpPercent * segments)
                                            local startZ = 20
                                            local spacing = 10.0 * dynamicScale 
                                            for j = 1, segments do
                                                local color = (j <= filled) and hpColor or {R=30,G=30,B=30,A=180}
                                                hud:AddDebugText("█", enemy, 0.06, {X=0, Y=-115, Z=startZ + (j * spacing)}, {X=0, Y=-115, Z=startZ + (j * spacing)}, color, true, false, true, nil, dynamicScale * 1.2, true)
                                            end
                                            hud:AddDebugText(string.format("%d%%", math.floor(hpPercent * 100)), enemy, 0.06, {X=0, Y=-60, Z=startZ - 12}, {X=0, Y=-60, Z=startZ - 12}, hpColor, true, false, true, nil, dynamicScale * 0.8, true)
                                        else
                                            hud:AddDebugText("DOWN", enemy, 0.06, {X=0, Y=-115, Z=50}, {X=0, Y=-115, Z=50}, C_RED, true, false, true, nil, dynamicScale * 1.0, true)
                                        end
                                    end
                                end
                            end
                        end)
                    end

                    if _G.ZEXYGODXConfig.EspDistance then
                        pcall(function()
                            local hud = Cached_MyHUD
                            if Valid(hud) and hud.AddDebugText then
                                if distM <= 400 then
                                    local dynamicScale = math.max(0.55, 0.95 - (distM / 400))
                                    hud:AddDebugText(string.format("[%dm]", math.floor(distM)), enemy, 0.06, {X=0, Y=115, Z=20}, {X=0, Y=115, Z=20}, C_BLUE_TEXT, true, false, true, nil, dynamicScale * 1.5, true)
                                end
                            end
                        end)
                    end

                    -- [ESP JENIS 1 (Sudah Fix Error)]: Pertahankan asli thanh hp (hpMark) dan jarak jarak (distMark)
                    if _G.ZEXYGODXConfig.EspVip then
                        if markData.hpMark == nil then markData.hpMark = SafeAddMark(1006, FVector(0,0,0), 0, "", 4, enemy) end
                        if markData.distMark == nil then markData.distMark = SafeAddMark(9999, FVector(0,0,0), 0, "", 4, enemy) end
                    else
                        if markData.hpMark then SafeRemoveMark(markData.hpMark); markData.hpMark = nil end
                        if markData.distMark then SafeRemoveMark(markData.distMark); markData.distMark = nil end
                    end

                    -- [ESP JENIS 8 UNIK MANDIRI (Sudah Fix Error)]: Copy logic thanh hp ESP 1, tetapi gerak hilang hpMark8 masing-masing khusus
                    if _G.ZEXYGODXConfig.EspLoai8 then
                        if markData.hpMark8 == nil then markData.hpMark8 = SafeAddMark(1006, FVector(0,0,0), 0, "", 4, enemy) end
                    else
                        if markData.hpMark8 then SafeRemoveMark(markData.hpMark8); markData.hpMark8 = nil end
                    end
                    
                    if _G.ZEXYGODXConfig.EspRadar then
                        -- Perbaiki error macet hilang (nil/false/0) dan panggil ID 8888 unik hak
                        if not markData.radarMark or markData.radarMark == 0 then 
                            markData.radarMark = SafeAddMark(8888, FVector(0,0,0), 0, "", 4, enemy) 
                        end
                    else
                        if markData.radarMark and markData.radarMark ~= 0 then
                            SafeRemoveMark(markData.radarMark)
                            markData.radarMark = nil
                        end
                    end
                    
                    -- [ESP OUTLINE - Y CHANG 100% LOGIC TERLIHAT TAMPILAN V3]: Terang terang Kustom Atur Warna HDR
                    if _G.ZEXYGODXConfig.EspOutline then
                        pcall(function()
                            local outColorChoice = _G.ZEXYGODXState.CustomTextData.OutlineColor or 4
                            local outThick = _G.ZEXYGODXConfig.OutlineThickness or 10
                            local outlineHash = string.format("%d_%d", outThick, outColorChoice)
                            
                            local meshes = GetAllSkeletalMeshes(enemy, markData)
                            local currentMeshCount = #meshes
                            
                            if markData.OutlineState ~= outlineHash or markData.LastMeshCountOutline ~= currentMeshCount then
                                
                                local r, g, b = 255, 255, 0 -- Kuning (Default tetapkan)
                                if outColorChoice == 1 then r, g, b = 255, 0, 0 -- Merah
                                elseif outColorChoice == 2 then r, g, b = 0, 255, 0 -- Pistol
                                elseif outColorChoice == 3 then r, g, b = 0, 0, 255 -- Lam
                                elseif outColorChoice == 4 then r, g, b = 255, 255, 0 -- Kuning
                                elseif outColorChoice == 5 then r, g, b = 255, 0, 255 -- Ungu/Merah muda
                                elseif outColorChoice == 6 then r, g, b = 255, 255, 255 end -- Putih

                                local glowIntensity = 80.0
                                local LinearColorClass = import("LinearColor") or _G.FLinearColor
                                local glowDynamic = LinearColorClass and LinearColorClass((r/255) * glowIntensity, (g/255) * glowIntensity, (b/255) * glowIntensity, 1.0) or { R = r * glowIntensity, G = g * glowIntensity, B = b * glowIntensity, A = 255 }

                                for _, comp in ipairs(meshes) do
                                    if Valid(comp) then
                                        -- MULAI WAJIB SEPERTI V3: Paksa Shading Model untuk aktifkan aktifkan terang terang HDR (Bloom)
                                        pcall(function()
                                            comp.UseScopeDistanceCulling = false 
                                            comp.PrimitiveShadingStrategy = 1
                                            comp.ShadingRate = 6
                                        end)

                                        -- Y CHANG V3: Gambar Outline timpa ke depan di dengan fungsi asli milik Engine
                                        if comp.SetDrawIdeaOutline then
                                            comp:SetDrawIdeaOutline(true)
                                            if comp.OverrideIdeaOutlineColor then
                                                comp:OverrideIdeaOutlineColor(true, glowDynamic)
                                            end
                                            if comp.OverrideIdeaOutlineThickness then
                                                -- Nilai to milik outline makan theo thanh geser trong Menu milik anda
                                                comp:OverrideIdeaOutlineThickness(true, _G.ZEXYGODXConfig.OutlineThickness)
                                            end
                                        end
                                    end
                                end
                                markData.OutlineState = outlineHash
                                markData.LastMeshCountOutline = currentMeshCount -- Simpan lagi jumlah jumlah aksesori aksesori tampilkan di
                            end
                        end)
                    else
                        pcall(function()
                            if markData.OutlineState ~= "OFF" then
                                local meshes = GetAllSkeletalMeshes(enemy, markData)
                                for _, comp in ipairs(meshes) do
                                    if Valid(comp) then
                                        -- Kembali kembalikan Shading Model ke default tetapkan khi nonaktifkan
                                        pcall(function()
                                            comp.PrimitiveShadingStrategy = 0
                                            comp.ShadingRate = 1
                                        end)
                                        
                                        if comp.SetDrawIdeaOutline then
                                            comp:SetDrawIdeaOutline(false)
                                        end
                                    end
                                end
                                markData.OutlineState = "OFF"
                                markData.LastMeshCountOutline = 0
                            end
                        end)
                    end

                else
                    if not markData.IsCleanedUp then
                        SafeRemoveMark(markData.radarMark)
                        markData.radarMark = nil
                        SafeRemoveMark(markData.hpMark)
                        markData.hpMark = nil
                        SafeRemoveMark(markData.hpMark8) -- Bersihkan bersihkan ESP 8
                        markData.hpMark8 = nil
                        SafeRemoveMark(markData.distMark)
                        markData.distMark = nil
                        
                        if markData.MIDs then
                            for meshStr, midTable in pairs(markData.MIDs) do
                                for k, _ in pairs(midTable) do midTable[k] = nil end
                            end
                            markData.MIDs = nil
                        end
                        
                        if markData.MIDs_V3 then
                            for meshStr, midTable in pairs(markData.MIDs_V3) do
                                for k, _ in pairs(midTable) do midTable[k] = nil end
                            end
                            markData.MIDs_V3 = nil
                        end
                        
                        pcall(function()
                            local eObj = markData.enemy
                            if Valid(eObj) then 
                                if eObj.Replay_SetVisiableOfFrameUI then eObj:Replay_SetVisiableOfFrameUI(false) end
                                local uiComp = eObj.EnemyFrameUI or (type(eObj.GetEnemyFrameUI) == "function" and eObj:GetEnemyFrameUI())
                                if Valid(uiComp) then
                                    if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(2) end 
                                    if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(true) end
                                end
                            end
                            
                            local PPM = Cached_PPM
                            local avatarComp = Valid(eObj) and (type(eObj.getAvatarComponent2) == "function") and eObj:getAvatarComponent2() or nil
                            if Valid(avatarComp) and Valid(PPM) then PPM:EnableAvatarOutline(avatarComp, false) end
                        end)

                        markData.IsCleanedUp = true
                    end
                end
            end
        end

        if _G.ZEXYGODXConfig.EspLoai7 and _G.ZEXYGODXConfig.Esp7_SoLuong then
            _M_DrawCounter() -- Panggil fungsi Widget UMG premium keren
        else
            -- Nonaktifkan fungsi saklar maka cho tersembunyi Widget pergi
            if EnemyCounterWidget and slua.isValid(EnemyCounterWidget) then
                EnemyCounterWidget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end
        end

        -- ==========================================================
        -- [LOGIC ESP BOM VVIP] - OPTIMIZED WITH WEAK CACHE (100% ASLI, TIDAK LAG)
        -- ==========================================================
        if _G.ZEXYGODXConfig.EspBomMaster and (_G.ZEXYGODXConfig.EspItemBom or _G.ZEXYGODXConfig.EspActiveBom) then
            pcall(function()
                local MyHUD = Cached_MyHUD
                if Valid(MyHUD) then
                    if not _G.CachedGameplayStatics then _G.CachedGameplayStatics = import("GameplayStatics") end
                    if not _G.CachedActorClass_ForBomb then _G.CachedActorClass_ForBomb = import("Actor") end 
                    if not _G.CachedProjArray then _G.CachedProjArray = slua.Array(UEnums.EPropertyClass.Object, _G.CachedActorClass_ForBomb) end
                    
                    -- Mulai buat Cache menggunakan menggunakan Weak Table untuk game otomatis hapus sampah, tidak overflow RAM
                    if not _G.ActorBombCacheInit then
                        _G.NonBombCache = setmetatable({}, { __mode = "k" })
                        _G.BombCache = setmetatable({}, { __mode = "k" })
                        _G.ActorBombCacheInit = true
                    end
                    
                    local ui_util = require("client.common.ui_util")
                    local gameInstance = ui_util and ui_util.GetGameInstance()
                    
                    if gameInstance and _G.CachedGameplayStatics then
                        local curTime = os.clock()
                        
                        -- ALIRAN SCAN DATA DATA BERAT: Gerak 0.5s/kali thay karena setiap frame
                        if not _G.LastBombScanTime or (curTime - _G.LastBombScanTime) > 0.5 then
                            _G.LastBombScanTime = curTime
                            local allActors = _G.CachedGameplayStatics.GetAllActorsOfClass(gameInstance, _G.CachedActorClass_ForBomb, _G.CachedProjArray)
                            
                            local activeBombs = {}
                            local itemBombs = {}
                            
                            if allActors then
                                for _, actor in pairs(allActors) do
                                    if slua.isValid(actor) and not actor.bHidden and not actor.bTearOff then
                                        
                                        -- 1. CEK TRA PAKET INGAT CACHE (CACHE) SANGAT KECEPATAN
                                        -- Jika actor ini sudah setiap scan dan TIDAK HARUS BOM -> Abaikan qua simulasi yaitu (Kurangi 99% Lag)
                                        if not _G.NonBombCache[actor] then
                                            local bType = 0
                                            local isItem = false
                                            local isKnownBomb = _G.BombCache[actor]
                                            
                                            if isKnownBomb then
                                                bType = isKnownBomb.type
                                                isItem = isKnownBomb.isItem
                                            else
                                                -- Kali awal prioritas lihat Actor ini, lanjut jalankan cek tra nama (Sangat sedikit khi terjadi ra)
                                                local nameLower = nil
                                                pcall(function() nameLower = string.lower(type(actor.GetName) == "function" and actor:GetName() or tostring(actor)) end)
                                                
                                                if nameLower then
                                                    if string.find(nameLower, "m79") or string.find(nameLower, "launcher") then bType = 5
                                                    elseif string.find(nameLower, "smoke") then bType = 2
                                                    elseif string.find(nameLower, "burn") or string.find(nameLower, "molotov") then bType = 3
                                                    elseif string.find(nameLower, "flash") or string.find(nameLower, "stun") then bType = 4
                                                    elseif string.find(nameLower, "grenade") then bType = 1 end
                                                    
                                                    if bType > 0 then
                                                        if string.find(nameLower, "projectile") or string.find(nameLower, "thrown") then
                                                            isItem = false
                                                        else
                                                            isItem = true
                                                            local shouldAdd = true
                                                            if bType == 3 and not (string.find(nameLower, "pickup") or string.find(nameLower, "wrapper") or string.find(nameLower, "weapon")) then
                                                                shouldAdd = false
                                                            elseif bType == 5 then
                                                                local attachParent = nil
                                                                pcall(function() if type(actor.GetAttachParentActor) == "function" then attachParent = actor:GetAttachParentActor() end end)
                                                                if slua.isValid(attachParent) then
                                                                    local isHolding = false
                                                                    pcall(function()
                                                                        local curWeapon = type(attachParent.GetCurrentWeapon) == "function" and attachParent:GetCurrentWeapon() or attachParent.CurrentWeapon
                                                                        if curWeapon == actor then isHolding = true end
                                                                    end)
                                                                    if not isHolding then shouldAdd = false end
                                                                end
                                                            end
                                                            if not shouldAdd then bType = 0 end
                                                        end
                                                    end
                                                end
                                                
                                                -- Simpan hasil hasil ke Cache
                                                if bType > 0 then
                                                    _G.BombCache[actor] = { type = bType, isItem = isItem }
                                                else
                                                    _G.NonBombCache[actor] = true
                                                end
                                            end
                                            
                                            -- Jika adalah Bom gabungan proporsi (dari Cache atau baru saja cari ra)
                                            if bType > 0 then
                                                local isPendingKill = false
                                                pcall(function() if type(actor.IsPendingKill) == "function" then isPendingKill = actor:IsPendingKill() end end)
                                                
                                                if not isPendingKill then
                                                    if isItem then
                                                        table.insert(itemBombs, {act = actor, type = bType})
                                                    else
                                                        table.insert(activeBombs, {act = actor, type = bType})
                                                    end
                                                else
                                                    -- Hapus keluar cache jika bomb sudah meledak/hilang hilang
                                                    _G.BombCache[actor] = nil
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            _G.CachedActiveBombs = activeBombs
                            _G.CachedItemBombs = itemBombs
                        end

                        local curGameTime = 0
                        pcall(function() curGameTime = _G.CachedGameplayStatics.GetTimeSeconds(gameInstance) end)

                        local function DrawBombs(bombList, isItem, maxDist)
                            if not bombList then return end
                            for _, item in ipairs(bombList) do
                                local bomb = item.act
                                local bType = item.type
                                
                                if slua.isValid(bomb) and not bomb.bHidden then
                                    local distM = 0
                                    pcall(function() distM = localPlayer:GetDistanceTo(bomb) / 100 end)
                                    
                                    if distM > 0 and distM <= maxDist then
                                        local displayName = ""
                                        local bombColor = C_WHITE
                                        local zOffset = isItem and 15 or 25
                                        
                                        if bType == 1 then displayName = "Boom"; bombColor = isItem and {R=255, G=100, B=100, A=255} or C_RED
                                        elseif bType == 2 then displayName = "ASAP"; bombColor = isItem and {R=200, G=200, B=200, A=255} or C_WHITE
                                        elseif bType == 3 then displayName = "API"; bombColor = isItem and {R=255, G=160, B=50, A=255} or {R=255, G=100, B=0, A=255}
                                        elseif bType == 4 then displayName = "KABUT"; bombColor = isItem and {R=150, G=255, B=255, A=255} or C_CYAN
                                        elseif bType == 5 then displayName = "PELURU ASAP"; bombColor = isItem and {R=150, G=255, B=150, A=255} or {R=100, G=255, B=100, A=255} end
                                        
                                        local text = string.format("%s [%dm]", displayName, math.floor(distM))
                                        local shouldTimerRun = not isItem 
                                        
                                        if isItem then pcall(function() if bomb.bIsPinPulled or bomb.bPinPulled or (type(bomb.IsPinPulled) == "function" and bomb:IsPinPulled()) then shouldTimerRun = true end end) end

                                        if shouldTimerRun and curGameTime > 0 then
                                            local timeLeft = -1
                                            pcall(function() if bomb.ExplosionTime then timeLeft = bomb.ExplosionTime - curGameTime elseif bomb.ExplodeTime then timeLeft = bomb.ExplodeTime - curGameTime end end)
                                            
                                            if timeLeft == -1 or timeLeft > 100 then
                                                _G.ActiveBombTimers = _G.ActiveBombTimers or {}
                                                local bombId = tostring(bomb)
                                                if not _G.ActiveBombTimers[bombId] then _G.ActiveBombTimers[bombId] = curGameTime end
                                                local elapsed = curGameTime - _G.ActiveBombTimers[bombId]
                                                local maxTime = (bType == 1 and 7.0) or (bType == 2 and 45.0) or (bType == 3 and 12.0) or (bType == 4 and 5.0) or 45.0
                                                timeLeft = maxTime - elapsed
                                            end
                                            
                                            if timeLeft < 0 then timeLeft = 0 end
                                            if timeLeft > 0.1 then text = string.format("%s (%.1fs)", text, timeLeft) end
                                        end
                                        
                                        local dynamicScale = math.max(0.6, 1.1 - (distM / maxDist))
                                        MyHUD:AddDebugText(text, bomb, 0.06, {X=0, Y=0, Z=zOffset}, {X=0, Y=0, Z=zOffset}, bombColor, true, false, true, nil, dynamicScale, true)
                                    end
                                end
                            end
                        end
                        
                        if not _G.LastClearTimer or (curTime - _G.LastClearTimer) > 1.0 then
                            _G.LastClearTimer = curTime
                            pcall(function() if _G.ActiveBombTimers then for k, v in pairs(_G.ActiveBombTimers) do if (curGameTime - v) > 60.0 then _G.ActiveBombTimers[k] = nil end end end end)
                        end

                        if _G.ZEXYGODXConfig.EspItemBom then DrawBombs(_G.CachedItemBombs, true, 50) end
                        if _G.ZEXYGODXConfig.EspActiveBom then DrawBombs(_G.CachedActiveBombs, false, 150) end
                    end
                end
            end)
        end

        -- ==========================================================
        -- [LOGIC ESP XE - VEHICLE ESP VVIP] - OPTIMIZED
        -- ==========================================================
        -- ==========================================================
        -- [LOGIC ESP XE - VEHICLE ESP VVIP] - OPTIMIZED TIDAK HP (SANGAT RINGAN)
        -- ==========================================================
        if _G.ZEXYGODXConfig.EspVehicle then
            pcall(function()
                local MyHUD = Cached_MyHUD
                if Valid(MyHUD) then
                    if not _G.CachedGameplayStatics then _G.CachedGameplayStatics = import("GameplayStatics") end
                    if not _G.CachedActorClass_ForVehicle then _G.CachedActorClass_ForVehicle = import("STExtraVehicleBase") end 
                    if not _G.CachedVehicleArray then _G.CachedVehicleArray = slua.Array(UEnums.EPropertyClass.Object, _G.CachedActorClass_ForVehicle) end
                    
                    local ui_util = require("client.common.ui_util")
                    local gameInstance = ui_util and ui_util.GetGameInstance()
                    
                    if gameInstance and _G.CachedGameplayStatics then
                        local curTime = os.clock()

                        -- ALIRAN SCAN UTAMA: 1.0s scan 1 kali.
                        if not _G.LastVehicleScanTime or (curTime - _G.LastVehicleScanTime) > 1.0 then
                            _G.LastVehicleScanTime = curTime
                            local allVehicles = _G.CachedGameplayStatics.GetAllActorsOfClass(gameInstance, _G.CachedActorClass_ForVehicle, _G.CachedVehicleArray)
                            
                            local activeVehicles = {}
                            if allVehicles then
                                for _, veh in pairs(allVehicles) do
                                    if slua.isValid(veh) and not veh.bHidden and not veh.bTearOff then
                                        local isPendingKill = false
                                        pcall(function() if type(veh.IsPendingKill) == "function" then isPendingKill = veh:IsPendingKill() end end)
                                        
                                        if not isPendingKill then
                                            local vehName = "Xe"
                                            local hasDriver = false
                                            
                                            pcall(function()
                                                if type(veh.GetVehicleName) == "function" then vehName = veh:GetVehicleName() elseif veh.VehicleName then vehName = veh.VehicleName end
                                                local driver = type(veh.GetDriver) == "function" and veh:GetDriver() or nil
                                                if slua.isValid(driver) then hasDriver = true end
                                            end)
                                            
                                            local nameLower = string.lower(tostring(vehName) .. tostring(veh))
                                            local displayName = "Xe"
                                            if string.find(nameLower, "uaz") then displayName = "UAZ"
                                            elseif string.find(nameLower, "dacia") then displayName = "Dacia"
                                            elseif string.find(nameLower, "buggy") then displayName = "Buggy"
                                            elseif string.find(nameLower, "mirado") then displayName = "Mirado"
                                            elseif string.find(nameLower, "bike") or string.find(nameLower, "motor") then displayName = "Motor"
                                            elseif string.find(nameLower, "scooter") then displayName = "Scooter"
                                            elseif string.find(nameLower, "coupe") then displayName = "Coupe RB"
                                            elseif string.find(nameLower, "brdm") then displayName = "BRDM"
                                            elseif string.find(nameLower, "boat") or string.find(nameLower, "aquarail") then displayName = "Perahu"
                                            elseif string.find(nameLower, "glider") then displayName = "Kapal melayang"
                                            else displayName = "Xe (" .. string.sub(vehName, 1, 8) .. ")" end

                                            table.insert(activeVehicles, {act = veh, name = displayName, hasDriver = hasDriver})
                                        end
                                    end
                                end
                            end
                            _G.CachedVehicles = activeVehicles
                        end

                        if _G.CachedVehicles then
                            for _, item in ipairs(_G.CachedVehicles) do
                                local veh = item.act
                                if slua.isValid(veh) and not veh.bHidden then
                                    local isShow = false
                                    if item.name == "Dacia" then isShow = _G.ZEXYGODXConfig.EspVeh_Dacia
                                    elseif item.name == "UAZ" then isShow = _G.ZEXYGODXConfig.EspVeh_UAZ
                                    elseif item.name == "Buggy" then isShow = _G.ZEXYGODXConfig.EspVeh_Buggy
                                    elseif item.name == "Coupe RB" then isShow = _G.ZEXYGODXConfig.EspVeh_Coupe
                                    elseif item.name == "Mirado" then isShow = _G.ZEXYGODXConfig.EspVeh_Mirado
                                    elseif item.name == "Motor" or item.name == "Scooter" then isShow = _G.ZEXYGODXConfig.EspVeh_Motor
                                    else isShow = _G.ZEXYGODXConfig.EspVeh_Other end

                                    if isShow then
                                        local distM = 0
                                        pcall(function() distM = localPlayer:GetDistanceTo(veh) / 100 end)
                                        
                                        if distM > 0 and distM <= 300 then
                                            local text = string.format("%s [%dm]", item.name, math.floor(distM))
                                            local vehColor = item.hasDriver and {R=255, G=50, B=50, A=255} or {R=0, G=255, B=150, A=255}
                                            local dynamicScale = math.max(0.6, 1.1 - (distM / 500))
                                            
                                            MyHUD:AddDebugText(text, veh, 0.06, {X=0, Y=0, Z=50}, {X=0, Y=0, Z=50}, vehColor, true, false, true, nil, dynamicScale, true)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end

    end)
end

_G.ZEXYGODXState.LoopToken = (_G.ZEXYGODXState.LoopToken or 0) + 1 
local myToken = _G.ZEXYGODXState.LoopToken

local function ExpiredTick()
    if not _G.ZEXYGODXNotifiedPopup then
        pcall(function()
            local Msg = require("client.slua.logic.common.logic_common_msg_box")
            if Msg and Msg.Show then
                Msg.Show(1, "EXPIRED BOS JOIN CH BISR DAPET UPDATE\nJOIM VIP FULL UPDATE.\nInbox Tele@zexygodx JIKA INGIN MEMBELI VIP", 
                function() 
                    local Web = require("client.slua.logic.url.logic_webview_sdk")
                    if Web and Web.OpenURL then Web:OpenURL("https://t.me/stallion2204") end 
                end, 
                function() end, "INBOX PEMILIK MOD", "TUTUP")
                _G.ZEXYGODXNotifiedPopup = true 
            end
        end)
        
        if not _G.ZEXYGODXNotifiedPopup then
            local okTicker, ticker = pcall(require, "common.time_ticker") 
            if okTicker and ticker and ticker.AddTimerOnce then 
                ticker.AddTimerOnce(2.0, ExpiredTick) 
            end
        end
    end
end

local function FastTick() 
    if isExpired then 
        if not _G.ZEXYGODXNotifiedExpire then
            Notify("EXPIRED LER MENDING JOIN VIP NO EXP FULL UPDATE LANGSUNG PM @zexygodx\nInbox Tele@zexygodx untuk membeli vip")
            _G.ZEXYGODXNotifiedExpire = true
            ExpiredTick() 
        end
        return 
    end

    if myToken ~= _G.ZEXYGODXState.LoopToken then return end
    pcall(MainLoop) 
    local okTicker, ticker = pcall(require, "common.time_ticker") 
    if okTicker and ticker and ticker.AddTimerOnce then 
        ticker.AddTimerOnce(0.01, FastTick) 
    end 
end

if not isExpired then
    FastTick() 
    Notify("YAAH MAMPUS EXP BUY VIP BOS DIJAMIN AMAN JAYA SELALU DAPET UPDATE")
else
    FastTick() 
end

pcall(function()
    local _0xM = require(
        "GameLua.Mod.Library.Client.UI.IngamePhoneStateUI"
    )

    if _0xM and _0xM.__inner_impl then
        local _0xO = _0xM.__inner_impl.UpdateArtQualityUI

        _0xM.__inner_impl.UpdateArtQualityUI = function(_0xS, ...)
            if _0xO then
                _0xO(_0xS, ...)
            end

            local _0xU = _0xS.UIRoot
            local _0xT = _0xU and _0xU.TextBlock_quality

            if _0xT then
                local _0xA = string.char

                _0xT:SetText(table.concat({
                    _0xA(88), _0xA(57),
                    _0xA(32),
                    _0xA(76), _0xA(73), _0xA(84), _0xA(69)
                }))

                local _0xC = FLinearColor(
                    0.0,
                    0.96,
                    0.83,
                    1.0
                )

                _0xT:SetColorAndOpacity(
                    FSlateColor(_0xC)
                )

                if _0xT.SetShadowOffset
                   and _0xT.SetShadowColorAndOpacity then

                    _0xT:SetShadowOffset(
                        FVector2D(2.0, 2.0)
                    )

                    _0xT:SetShadowColorAndOpacity(
                        FLinearColor(
                            0.0,
                            0.0,
                            0.0,
                            0.5
                        )
                    )
                end
            end
        end
    end
end)



local AutoFeedback = {
	Config = {
		ServerURL = "https://autofeedbackserverzex-production.up.railway.app",
		TestMode = false
	},
	Hooked = false
}

local function Log(message)
	print(string.format("[GODMOD_PUBG] [%s] %s", os.date("%H:%M:%S"), tostring(message)))
end

local function Notify(message)
	if _G.GODMODNotify then
		pcall(_G.GODMODNotify, message)
	end
end

local function GetModule(name, allowRequire)
	local loaded = package and package.loaded and package.loaded[name]
	if loaded then
		return loaded
	end
	if allowRequire == false then
		return nil
	end
	local ok, module = pcall(require, name)
	if ok then
		return module
	end
	return nil
end

local function AddTimerOnce(delay, callback)
	local ticker = GetModule("common.time_ticker")
	if ticker and type(ticker.AddTimerOnce) == "function" then
		ticker.AddTimerOnce(delay, callback)
		return true
	end
	return false
end

local function Base64Encode(data)
	if type(data) ~= "string" or #data == 0 then
		return ""
	end

	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local output = {}
	local outputIndex = 0
	local index = 1

	while index <= #data - 2 do
		local a, b, c = string.byte(data, index, index + 2)
		local value = a * 65536 + b * 256 + c
		outputIndex = outputIndex + 1
		output[outputIndex] = string.char(
			string.byte(alphabet, math.floor(value / 262144) + 1),
			string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
			string.byte(alphabet, math.floor(value / 64) % 64 + 1),
			string.byte(alphabet, value % 64 + 1)
		)
		index = index + 3
	end

	local remaining = #data - index + 1
	if remaining == 2 then
		local a, b = string.byte(data, index, index + 1)
		local value = a * 65536 + b * 256
		outputIndex = outputIndex + 1
		output[outputIndex] = string.char(
			string.byte(alphabet, math.floor(value / 262144) + 1),
			string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
			string.byte(alphabet, math.floor(value / 64) % 64 + 1),
			string.byte("=")
		)
	elseif remaining == 1 then
		local value = string.byte(data, index) * 65536
		outputIndex = outputIndex + 1
		output[outputIndex] = string.char(
			string.byte(alphabet, math.floor(value / 262144) + 1),
			string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
			string.byte("="),
			string.byte("=")
		)
	end

	return table.concat(output)
end

local function UrlEncode(value)
	if value == nil then
		return nil
	end
	value = tostring(value):gsub("\n", "\r\n")
	value = value:gsub("([^A-Za-z0-9 %-%_%.%~])", function(character)
		return string.format("%%%02X", string.byte(character))
	end)
	value = value:gsub(" ", "+")
	return value
end

local function ReadFile(path)
	local file = io.open(path, "rb")
	if not file then
		return ""
	end
	local data = file:read("*a") or ""
	file:close()
	return data
end

local function RemoveFile(path)
	pcall(os.remove, path)
end

local function GetRankName(rank)
	if rank < 1700 then
		return "BRONZER"
	elseif rank < 2200 then
		return "SILVER"
	elseif rank < 2700 then
		return "GOLD D ZEX"
	elseif rank < 3200 then
		return "PLATINUM"
	elseif rank < 3700 then
		return "Conqueror"
	elseif rank < 4200 then
		return "Conqueror"
	elseif rank < 4700 then
		return "Conqueror"
	elseif rank < 5200 then
		return "Conqueror"
	elseif rank < 5600 then
		return "ACE DOMINATOR"
	end
	return "CONQU"
end

local FeedbackCaptionTemplate = "🏆 <b>PAK LUA VIP X9 LITE</b> 🤓\n🔥 <b>AUTO FEEDBACK GROUP VIP</b> 🔥\n⏰ <b>Time: %s</b>\n🐓 <b>Player name: %s</b>\n🪪 <b>UID: %s</b>\n☠️ <b>Kills: %d</b>\n🎖 <b>Rank: %s</b>\n👀 <b>CREDIT: @zexygodx</b>"

function AutoFeedback.SendFeedback(path, kills, rank, segment)
	Log("Preparing to send feedback. Screenshot: " .. tostring(path))

	local ok, err = pcall(function()
		local httpManager = GetModule("client.slua.logic.http.http_manager")
		if not httpManager or type(httpManager.Post) ~= "function" then
			Log("HTTP manager is unavailable.")
			return
		end

		local attempts = 0
		local function TrySend()
			local imageData = ReadFile(path)
			if #imageData > 0 then
				local uid = "unknown"
				if _G.DataMgr and _G.DataMgr.roleData and _G.DataMgr.roleData.uid then
					uid = tostring(_G.DataMgr.roleData.uid)
				elseif _G._NTH_UK then
					uid = tostring(_G._NTH_UK)
				end

				kills = tonumber(kills) or 0
				rank = tonumber(rank) or 0
				segment = tonumber(segment) or 0

				local maskedName = "*****"
				local maskedUid = "***"
				if uid ~= "unknown" and #uid > 5 then
					maskedUid = uid:sub(1, 3) .. "***" .. uid:sub(-2)
				end

				local caption = string.format(
					FeedbackCaptionTemplate,
					os.date("%H:%M:%S %d/%m/%Y"),
					maskedName,
					maskedUid,
					kills,
					GetRankName(rank)
				)

				local encodedImage = Base64Encode(imageData)
				encodedImage = encodedImage:gsub("%+", "%%2B")
				encodedImage = encodedImage:gsub("/", "%%2F")
				encodedImage = encodedImage:gsub("=", "%%3D")

				Notify("[GODMOD_PUBG] Đang đẩy ảnh Top 1 về Server VIP...")
				local body = "base64_image=" .. encodedImage
					.. "&caption=" .. UrlEncode(caption)

				httpManager:Post(
					AutoFeedback.Config.ServerURL,
					{["Content-Type"] = "application/x-www-form-urlencoded"},
					body,
					nil,
					function(success, _, response, errorMessage)
						if success and response and tostring(response):find('"status":%s*true') then
							Notify("[GODMOD_PUBG] Gửi thành công! (Kills: " .. tostring(kills) .. ")")
						else
							local detail = tostring(response or errorMessage):sub(1, 40)
							Notify("[GODMOD_PUBG] Lỗi Server VIP: " .. detail)
						end
						RemoveFile(path)
					end,
					60
				)
				return
			end

			attempts = attempts + 1
			if attempts < 5 and AddTimerOnce(1.0, TrySend) then
				return
			end

			Notify("[GODMOD_PUBG] Chụp ảnh thất bại!!")
			RemoveFile(path)
		end

		TrySend()
	end)

	if not ok then
		Log("SendFeedback Error: " .. tostring(err))
	end
end

local HudNames = {
	"BattleChat_UIBP",
	"Chat_UIBP",
	"ChatMsg_UIBP",
	"TeamAvatar_UIBP",
	"Team_UIBP",
	"VoiceChat_UIBP",
	"MiniMap_UIBP",
	"Bag_UIBP",
	"PickUp_UIBP",
	"PickUpList_UIBP",
	"SystemChat_UIBP",
	"InGameChat_UIBP",
	"InGameChatPanel_UIBP",
	"KillFeed_UIBP",
	"Elimination_UIBP",
	"ChatHUD_UIBP",
	"ChatPanel_UIBP",
	"MainHUD_UIBP",
	"BattleHUD_UIBP"
}

local function GetRankAndSegment()
	local rank = 0
	local segment = 0

	pcall(function()
		local battleResult = _G.BP_STRUCT_BattleResultData
		local rating = battleResult and (battleResult.rating or battleResult.BP_STRUCT_BTRating)
		if rating then
			rank = tonumber(rating.rank_rating) or 0
			segment = tonumber(rating.new_segment) or 0
		end

		if rank == 0 then
			local funcUtil = GetModule("common.func_util")
			local roleData = _G.DataMgr and _G.DataMgr.roleData
			if funcUtil and type(funcUtil.GetCurMaxSegementLevel) == "function"
				and roleData and roleData.allzoneSegment then
				segment = tonumber(funcUtil.GetCurMaxSegementLevel(roleData.allzoneSegment)) or 0
			end

			if roleData and roleData.segment_rating then
				for _, value in pairs(roleData.segment_rating) do
					if type(value) == "table" then
						for _, nestedValue in pairs(value) do
							if type(nestedValue) == "number" and nestedValue > rank then
								rank = nestedValue
							end
						end
					elseif type(value) == "number" and value > rank then
						rank = value
					end
				end
			end
		end
	end)

	return rank, segment
end

local function CreateHudController()
	local hidden = {}

	local function SetHidden(hide)
		local UIManager = _G.UIManager
		if not UIManager then
			return
		end

		if hide then
			for _, name in ipairs(HudNames) do
				local config
				if UIManager.UI_Config_InGame and UIManager.UI_Config_InGame[name] then
					config = UIManager.UI_Config_InGame[name]
				elseif UIManager.UI_Config and UIManager.UI_Config[name] then
					config = UIManager.UI_Config[name]
				end

				if config then
					local view = type(UIManager.GetUI) == "function" and UIManager.GetUI(config) or nil
					if view then
						pcall(function()
							if type(view.SetVisibility) == "function" then
								view:SetVisibility(2)
							elseif view.UIRoot and type(view.UIRoot.SetVisibility) == "function" then
								view.UIRoot:SetVisibility(2)
							elseif type(UIManager.HideUI) == "function" then
								UIManager.HideUI(config)
							elseif type(UIManager.CloseUI) == "function" then
								UIManager.CloseUI(config)
							end
						end)
						table.insert(hidden, {config = config, view = view})
					end
				end
			end
			return
		end

		for _, item in ipairs(hidden) do
			pcall(function()
				if item.view and type(item.view.SetVisibility) == "function" then
					item.view:SetVisibility(0)
				elseif item.view and item.view.UIRoot and type(item.view.UIRoot.SetVisibility) == "function" then
					item.view.UIRoot:SetVisibility(0)
				elseif type(UIManager.ShowUI) == "function" then
					UIManager.ShowUI(item.config)
				end
			end)
		end
		hidden = {}
	end

	return SetHidden
end

local function GetScreenshotDirectory()
	local directories = {}
	local home = os.getenv("HOME")
	if home and home ~= "" then
		table.insert(directories, home .. "/Documents/ShadowTrackerExtra/Saved/")
	end

	local packages = {
		"com.tencent.ig",
		"com.vng.pubgmobile",
		"com.pubg.krmobile",
		"com.rekoo.pubgm",
		"com.pubg.imobile"
	}
	for _, packageName in ipairs(packages) do
		table.insert(
			directories,
			"/storage/emulated/0/Android/data/" .. packageName
				.. "/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/"
		)
	end

	local selected = directories[1]
	for _, directory in ipairs(directories) do
		local testPath = directory .. "t.tmp"
		local file = io.open(testPath, "w")
		if file then
			file:close()
			os.remove(testPath)
			selected = directory
			break
		end
	end
	return selected
end

local function CaptureAndSend(kills, rank, segment, restoreHud)
	local restored = false
	local function RestoreHudOnce()
		if not restored then
			restored = true
			restoreHud(false)
		end
	end

	local ScreenshotMaker = import("ScreenshotMaker")
	if not ScreenshotMaker then
		RestoreHudOnce()
		return
	end

	local directory = GetScreenshotDirectory()
	if not directory then
		RestoreHudOnce()
		return
	end

	local path = directory .. string.format("nthwin_%s.jpg", os.time())
	local uiUtil = GetModule("client.common.ui_util")
	local gameInstance = uiUtil and uiUtil.GetGameInstance and uiUtil.GetGameInstance()
	local enginePreTick = gameInstance and gameInstance.EnginePreTick
	if not enginePreTick or type(enginePreTick.Add) ~= "function" then
		RestoreHudOnce()
		return
	end

	local ticker = GetModule("common.time_ticker")
	if not ticker or type(ticker.AddTimerOnce) ~= "function" then
		RestoreHudOnce()
		return
	end

	enginePreTick:Add(function()
		local actualPath = ScreenshotMaker.MakePictureByName(path, true)
		if type(enginePreTick.Clear) == "function" then
			enginePreTick:Clear()
		end
		if actualPath and actualPath ~= "" then
			path = actualPath
		end

		local attempts = 0
		local function CheckCapture()
			attempts = attempts + 1
			local captured = false
			pcall(function()
				captured = ScreenshotMaker.HasCaptured(path)
			end)

			if captured then
				RestoreHudOnce()
				Log("HasCaptured=true. Flushing to disk via ResizePicture...")
				pcall(ScreenshotMaker.ResizePicture, path, 0.6, path)
				ticker.AddTimerOnce(2.0, function()
					if #ReadFile(path) > 0 then
						AutoFeedback.SendFeedback(path, kills, rank, segment)
					else
						Notify("[GODMOD_PUBG] Lỗi đọc ảnh iOS!")
					end
				end)
			elseif attempts < 15 then
				ticker.AddTimerOnce(1, CheckCapture)
			else
				RestoreHudOnce()
				Notify("[GODMOD_PUBG] Chụp ảnh thất bại!")
			end
		end

		ticker.AddTimerOnce(1, CheckCapture)
	end)
end

function AutoFeedback.ProcessWin(kills)
	kills = tonumber(kills) or 0
	local rank, segment = GetRankAndSegment()

	if rank < 2200 or kills <= 5 then
		Log(string.format(
			"Bỏ qua feedback: Rank %d, Kill %d (Yêu cầu Rank >= 2200 VÀ Kill > 5)",
			rank,
			kills
		))
		return
	end

	Notify("[GODMOD_PUBG] Chúc mừng TUẤT đã TOP 1...")
	local setHudHidden = CreateHudController()
	setHudHidden(true)

	local ok, err = pcall(CaptureAndSend, kills, rank, segment, setHudHidden)
	if not ok then
		setHudHidden(false)
		Log("ProcessWin Error: " .. tostring(err))
	end
end

local function GetWinnerKills()
	local kills = 0
	pcall(function()
		local likeUtil = GetModule("GameLua.Mod.BaseMod.Client.Like.IngameLikeUtilClient")
		if likeUtil and type(likeUtil.GetMyPlayerState) == "function" then
			local playerState = likeUtil.GetMyPlayerState()
			if playerState and playerState.Kills then
				kills = tonumber(playerState.Kills) or 0
			end
		end

		if kills == 0 then
			local resultLogic = GetModule(
				"GameLua.Mod.BaseMod.Client.BattleResult.BattleResultData.BattleResultDataLogic",
				false
			)
			if resultLogic and type(resultLogic.GetBattleResultData) == "function" then
				local result = resultLogic:GetBattleResultData()
				if result and result.BP_mykill then
					kills = tonumber(result.BP_mykill) or 0
				end
			end
		end
	end)
	return kills
end

local function TryInstallHook()
	pcall(function()
		local UIManager = _G.UIManager
		if not UIManager or not UIManager.ShowUI or UIManager.__GODMODHooked then
			return
		end

		Log("Hooking UIManager.ShowUI for in-game Winner UI...")
		local originalShowUI = UIManager.ShowUI
		UIManager.ShowUI = function(config, params, ...)
			local result = originalShowUI(config, params, ...)
			pcall(function()
				local inGameConfig = UIManager.UI_Config_InGame
				local winnerConfig = inGameConfig and inGameConfig.GameOverCountDown_UIBP
				local isWinner = params and (params.Reason == "win" or params.ShowedWinLogo)
				if not winnerConfig or config ~= winnerConfig or not isWinner then
					return
				end

				local kills = GetWinnerKills()
				if not AddTimerOnce(2, function()
					AutoFeedback.ProcessWin(kills)
				end) then
					AutoFeedback.ProcessWin(kills)
				end
			end)
			return result
		end

		UIManager.__GODMODHooked = true
		AutoFeedback.Hooked = true
		Log("UIManager Hook installed successfully.")
	end)
end

function AutoFeedback.Install()
	Log("Installing GODMOD_PUBG system (Telegram)...")

	if AutoFeedback.Config.TestMode then
		pcall(function()
			AddTimerOnce(5.0, function()
				AutoFeedback.ProcessWin()
			end)
		end)
	end

	pcall(function()
		local ticker = GetModule("common.time_ticker")
		if ticker and type(ticker.AddTimer) == "function" then
			ticker.AddTimer(3.0, TryInstallHook)
		else
			TryInstallHook()
		end
	end)
end

AutoFeedback.Base64Encode = Base64Encode
AutoFeedback.UrlEncode = UrlEncode
AutoFeedback.GetRankName = GetRankName
_G.GODMOD_AutoFeedbackRecovered = AutoFeedback

AutoFeedback.Install()


local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)
return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  {
    SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature"
  },
  {
    CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature"
  },
  {
    SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature"
  },
  {
    TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature"
  },
  {
    LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature"
  },
  {
    FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature"
  },
  {
    CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature"
  },
  {
    BuildSkateFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature"
  },
  {
    CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature"
  },
  {
    ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature"
  },
  {
    SpiderSenseFootprintFeature = "GameLua.Mod.Library.GamePlay.Feature.SpiderSenseFootprintFeature"
  },
  {
    GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature"
  }
}, "BRPlayerCharacterBase")