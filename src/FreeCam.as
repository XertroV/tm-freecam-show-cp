const uint ActiveCamControlOffset = 0x68;

uint16 GetOffset(const string &in className, const string &in memberName) {
    // throw exception when something goes wrong.
    auto ty = Reflection::GetType(className);
    auto memberTy = ty.GetMember(memberName);
    return memberTy.Offset;
}

CGameControlCameraFree@ GetFreeCamControls(CGameCtnApp@ app) {
    if (app is null) return null;
    if (app.GameScene is null) return null;
    if (app.CurrentPlayground is null) return null;
    // get the game camera struct
    // orig 0x2b8; GameScene at 0x2a8
    auto gameCamCtrl = Dev::GetOffsetNod(app, GetOffset("CGameManiaPlanet", "GameScene") + 0x10);
    if (gameCamCtrl is null) return null;
    if (Dev::GetOffsetUint64(gameCamCtrl, ActiveCamControlOffset) & 0xF != 0) return null;
    return cast<CGameControlCameraFree>(Dev::GetOffsetNod(gameCamCtrl, ActiveCamControlOffset));
}

bool g_IsInFreeCam = false;
CGameControlCameraFree@ g_FreeCamControl = null;
vec3 g_PlayerPos = vec3();
vec3 g_CameraPos = vec3();

void RenderEarly() {
    if (!ShowWindow) {
        @g_FreeCamControl = null;
        g_IsInFreeCam = false;
        return;
    }
    auto app = GetApp();
    @g_FreeCamControl = GetFreeCamControls(app);
    g_IsInFreeCam = g_FreeCamControl !is null;
    g_PlayerPos = vec3();
    g_CameraPos = Camera::GetCurrentPosition();

    auto cp = cast<CSmArenaClient>(app.CurrentPlayground);
    if (app.GameScene is null || cp is null)
        return;

    CSmScriptPlayer@ localPlayer = null;
    try {
        @localPlayer = cast<CSmScriptPlayer>(cast<CSmPlayer>(cp.GameTerminals[0].ControlledPlayer).ScriptAPI);
    } catch {}
    if (localPlayer is null) return;
    g_PlayerPos = localPlayer.Position;
}
