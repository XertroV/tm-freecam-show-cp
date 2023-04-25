const string PluginIcon = Icons::Search;
const string MenuTitle = "\\$af3" + PluginIcon + "\\$z " + Meta::ExecutingPlugin().Name;

[Setting hidden]
bool ShowWindow = false;

/** Render function called every frame intended only for menu items in `UI`. */
void RenderMenu() {
    if (UI::MenuItem(MenuTitle, "", ShowWindow)) {
        ShowWindow = !ShowWindow;
    }
}

uint lastViewTime = 0;
uint lastViewIndex = 0;
AnimMgr@ CamAnimMgr = AnimMgr(true);

const float TAU = Math::PI * 2.;

class WaypointInfo {
    vec3 pos;
    uint order;
    string tag;
    // index in MapLandmarks
    uint index;
    string label;
    float dist;
    float camDist;
    bool drawCpIndicator = false;

    WaypointInfo(uint index, CGameScriptMapLandmark@ lm) {
        this.index = index;
        pos = lm.Position;
        order = lm.Order;
        tag = lm.Tag;
    }

    void UpdateDistToPlayer() {
        dist = (g_PlayerPos - pos).Length();
        camDist = (g_CameraPos - pos).Length();
    }

    void DrawTableRow() {
        UI::TableNextRow();
        UI::TableNextColumn();
        UI::AlignTextToFramePadding();
        UI::Text("" + index + ".");

        UI::TableNextColumn();
        UI::Text(tag);

        UI::TableNextColumn();
        if (order > 0) {
            UI::Text("\\$888" + order);
            AddSimpleTooltip("This is the 'Order' of the CP -- all linked CPs have the same order.");
        }

        UpdateDistToPlayer();
        UI::TableNextColumn();
        UI::Text(Text::Format("%.1f", dist));
        UI::TableNextColumn();
        UI::Text(Text::Format("\\$999%.1f", camDist));

        UI::TableNextColumn();
        UI::SetNextItemWidth(UI::GetContentRegionAvail().x - 10.);
        label = UI::InputText("##cp-label-"+index, label);

        UI::TableNextColumn();
        UI::BeginDisabled(!g_IsInFreeCam);
        if (UI::Button("View##cp-" + index)) {
            startnew(CoroutineFunc(ViewMe));
        }
        UI::EndDisabled();
        UI::SameLine();
    }

    float viewExtraYaw = 0.0;
    uint lastAnimStart = 0;


    float g_StartingHAngle = 0;
    float g_StartingVAngle = 0;
    float g_EndingHAngle = 0;
    float g_EndingVAngle = 0;
    float g_StartingTargetDist = 0;
    float g_EndingTargetDist = 0;
    vec3 g_StartingPos();
    vec3 g_EndingPos();


    void ViewMe() {
        if (g_FreeCamControl is null) return;

        auto fc = g_FreeCamControl;
        // when true, rotate around a cp rather than snapping / zooming to it
        bool animInstead = index == lastViewIndex && (Time::Now - lastViewTime) < 3000;
        lastViewIndex = index;
        lastViewTime = Time::Now;

        @CamAnimMgr = AnimMgr(false, animDuration);

        if (!animInstead) {
            auto camToCp = pos - g_CameraPos;
            g_StartingPos = pos;
            g_EndingPos = pos;

            g_StartingTargetDist = camToCp.Length();
            g_EndingTargetDist = 40.;

            auto dir = camToCp.Normalized();
            auto startYP = DirToLookYawPitch(dir);
            g_StartingHAngle = fc.m_Yaw; // startYP.x;
            g_StartingVAngle = fc.m_Pitch; // startYP.y;

            // g_EndingHAngle = -0.8 + viewExtraYaw;
            g_EndingHAngle = startYP.x;
            g_EndingVAngle = startYP.y;

            // fc.m_Radius = 40.;
            // fc.m_Pitch = 0.8;
            // fc.m_Yaw = -0.8 + viewExtraYaw;
            viewExtraYaw += Math::PI / 2.0;
            // allow cam to update
            // yield();
            // @fc = g_FreeCamControl;
            // // copy calculated location so we don't have to worry about doing trig
            // fc.m_FreeVal_Loc_Translation = fc.Pos;
            // fc.m_TargetIsEnabled = false;

            auto animStarted = Time::Now;
            lastAnimStart = animStarted;
            // animate rotation first

            @CamAnimMgr = AnimMgr(false, animDuration / 2);

            while (!CamAnimMgr.IsDone && g_IsInFreeCam) {
                if (lastAnimStart != animStarted) {
                    // another animation is going on, so let it handle everything.
                    return;
                }
                CamAnimMgr.Update(true);
                g_FreeCamControl.m_Pitch = SimplifyRadians(AngleLerp(g_StartingVAngle, g_EndingVAngle, CamAnimMgr.t));
                g_FreeCamControl.m_Yaw = SimplifyRadians(AngleLerp(g_StartingHAngle, g_EndingHAngle, CamAnimMgr.t));
                yield();
            }


            g_StartingHAngle = startYP.x;
            g_StartingVAngle = startYP.y;

            g_EndingHAngle = startYP.x;
            g_EndingVAngle = Math::Clamp(startYP.y, 0.3, 0.8);

            fc.m_TargetPos = pos;
            fc.m_TargetIsEnabled = true;

            @CamAnimMgr = AnimMgr(false, animDuration);


            while (!CamAnimMgr.IsDone && g_IsInFreeCam) {
                if (lastAnimStart != animStarted) {
                    // another animation is going on, so let it handle everything.
                    return;
                }
                CamAnimMgr.Update(true);

                g_FreeCamControl.m_Radius = Math::Lerp(g_StartingTargetDist, g_EndingTargetDist, CamAnimMgr.t);
                g_FreeCamControl.m_Pitch = SimplifyRadians(AngleLerp(g_StartingVAngle, g_EndingVAngle, CamAnimMgr.t));
                g_FreeCamControl.m_Yaw = SimplifyRadians(AngleLerp(g_StartingHAngle, g_EndingHAngle, CamAnimMgr.t));

                yield();
            }

            if (g_IsInFreeCam) {
                g_FreeCamControl.m_FreeVal_Loc_Translation = g_FreeCamControl.Pos;
                g_FreeCamControl.m_TargetIsEnabled = false;
            }
        } else {
            g_FreeCamControl.m_TargetPos = pos;
            g_FreeCamControl.m_TargetIsEnabled = true;
            auto origYaw = fc.m_Yaw;
            auto newYaw = origYaw + Math::PI / 2.;
            viewExtraYaw += Math::PI / 2.0;

            auto animStarted = Time::Now;
            lastAnimStart = animStarted;

            while (!CamAnimMgr.IsDone && g_IsInFreeCam) {
                if (lastAnimStart != animStarted || g_FreeCamControl is null) {
                    // another animation is going on, so let it handle everything.
                    return;
                }
                CamAnimMgr.Update(true);
                g_FreeCamControl.m_Yaw = Math::Lerp(origYaw, newYaw, CamAnimMgr.t);
                yield();
            }

            if (g_IsInFreeCam) {
                g_FreeCamControl.m_FreeVal_Loc_Translation = g_FreeCamControl.Pos;
                g_FreeCamControl.m_TargetIsEnabled = false;
            }
        }
    }

    vec2 DirToLookYawPitch(vec3 &in dir) {
        auto xz = (dir * vec3(1, 0, 1)).Normalized();
        auto pitch = -Math::Asin(Math::Dot(dir, vec3(0, 1, 0)));
        auto yaw = Math::Asin(Math::Dot(xz, vec3(1, 0, 0)));
        if (Math::Dot(xz, vec3(0, 0, -1)) > 0) {
            yaw = - yaw - Math::PI;
        }
        return vec2(yaw, pitch);
    }

    float AngleLerp(float start, float stop, float t) {
        float diff = stop - start;
        while (diff > Math::PI) { diff -= TAU; }
        while (diff < -Math::PI) { diff += TAU; }
        return start + diff * t;
    }

    float SimplifyRadians(float a) {
        uint count = 0;
        while (Math::Abs(a) > TAU / 2.0 && count < 100) {
            a += (a < 0 ? 1. : -1.) * TAU;
            count++;
        }
        return a;
    }
}

string wpCachedForMapUid;
WaypointInfo@[] waypoints;

enum MapperSetting {
    None = 0, Ordered = 65536, Disabled = 65537, XDD = 65539
}

MapperSetting currMapCPIndicatorSetting = MapperSetting::None;

MapperSetting GetMapCPIndicatorSetting(CSmArena@ Arena, CGameCtnChallenge@ Map) {
    auto comment = string(Map.Comments).ToLower();
    if (comment.Contains('/uci order')) {
        return MapperSetting::Ordered;
    } else if (comment.Contains('/uci hide')) {
        return MapperSetting::Disabled;
    } else if (comment.Contains('/uci xdd')) {
        return MapperSetting::XDD;
    }

    uint StartOrder = 0;
    for (uint i = 0; i < Arena.MapLandmarks.Length; i++) {
        auto lm = Arena.MapLandmarks[i];
        // starting block
        if (lm.Waypoint is null && lm.Order > 65535) {
            StartOrder = lm.Order;
            break;
        }
        if (lm.Waypoint is null) continue;
        // multilap -- we keep going b/c maybe there's a starting block
        if (lm.Waypoint.IsMultiLap && lm.Order > 65535) {
            StartOrder = lm.Order;
            continue;
        }
    }

    if (StartOrder > 65535) {
        if ((StartOrder - 65535) & 2 > 0) return MapperSetting::Disabled;
        if ((StartOrder - 65535) & 1 > 0) return MapperSetting::Ordered;
        if ((StartOrder - 65535) & 4 > 0) return MapperSetting::XDD;
    }

    return MapperSetting::None;
}

void CacheWaypoints(CSmArenaClient@ cp) {
    waypoints.RemoveRange(0, waypoints.Length);
    wpCachedForMapUid = "";

    if (cp is null || cp.Arena is null) return;
    if (cp.Map is null) return;
    if (cp.Arena.MapLandmarks.Length == 0) return;

    wpCachedForMapUid = cp.Map.EdChallengeId;
    currMapCPIndicatorSetting = GetMapCPIndicatorSetting(cp.Arena, cp.Map);
    if (currMapCPIndicatorSetting == MapperSetting::Disabled) {
        // disabled by map so return immediately
        trace('Not caching CPs due to map setting: ' + tostring(currMapCPIndicatorSetting));
        return;
    }

    for (uint i = 0; i < cp.Arena.MapLandmarks.Length; i++) {
        waypoints.InsertLast(WaypointInfo(i, cp.Arena.MapLandmarks[i]));
    }
}

void SortCPsByDistance() {
    for (uint i = 0; i < waypoints.Length; i++) {
        waypoints[i].UpdateDistToPlayer();
    }
    waypoints.Sort(WaypointDistLess);
}

bool WaypointDistLess(const WaypointInfo@ &in a, const WaypointInfo@ &in b) {
    return a.dist < b.dist;
}

/** Render function called every frame.
*/
void RenderInterface() {
    if (!ShowWindow) return;
    auto app = cast<CGameManiaPlanet>(GetApp());
    auto map = app.RootMap;
    if (map is null) return;
    auto cp = cast<CSmArenaClient>(app.CurrentPlayground);
    if (cp is null || cp.Arena is null) return;
    if (app.GameScene is null) return;

    UpdateFreeCam_RenderEarly();

    if (S_OnlyShowInCam7 && !g_IsInFreeCam) return;

    if (wpCachedForMapUid != map.EdChallengeId) {
        CacheWaypoints(cp);
    }

    vec2 size = vec2(550, 300);
    vec2 pos = (vec2(Draw::GetWidth(), Draw::GetHeight()) - size) / 2.;
    UI::SetNextWindowSize(int(size.x), int(size.y), UI::Cond::FirstUseEver);
    UI::SetNextWindowPos(int(pos.x), int(pos.y), UI::Cond::FirstUseEver);
    UI::PushStyleColor(UI::Col::FrameBg, vec4(.2, .2, .2, .5));
    if (UI::Begin(MenuTitle, ShowWindow)) {
        UI::AlignTextToFramePadding();
        UI::Text("FreeCam detected: " + g_IsInFreeCam);
        UI::SameLine();
        if (UI::Button("Sort by Distance")) {
            SortCPsByDistance();
        }
        UI::SameLine();
        UI::BeginDisabled();
        UI::Text("Map CPI Setting: " + tostring(currMapCPIndicatorSetting));
        UI::EndDisabled();
        S_OnlyShowInCam7 = UI::Checkbox("Show window only when in cam 7", S_OnlyShowInCam7);

        bool disabled = currMapCPIndicatorSetting == MapperSetting::Disabled;

        if (UI::BeginChild("cp child")) {
            if (disabled) {
                UI::Text("Plugin disabled by mapper request.");
            } else if(UI::BeginTable("cp-table", 7, UI::TableFlags::SizingFixedFit)) {
                UI::TableSetupColumn("#", UI::TableColumnFlags::WidthFixed, 30.);
                UI::TableSetupColumn("Type", UI::TableColumnFlags::WidthFixed, 140.);
                UI::TableSetupColumn("##Order", UI::TableColumnFlags::WidthFixed, 40.);
                UI::TableSetupColumn("Dist", UI::TableColumnFlags::WidthFixed, 60.);
                UI::TableSetupColumn("Cam D.", UI::TableColumnFlags::WidthFixed, 60.);
                UI::TableSetupColumn("Label", UI::TableColumnFlags::WidthStretch);
                UI::TableSetupColumn("", UI::TableColumnFlags::WidthFixed);

                UI::TableHeadersRow();

                UI::ListClipper clip(waypoints.Length);
                while (clip.Step()) {
                    for (int i = clip.DisplayStart; i < clip.DisplayEnd; i++) {
                        waypoints[i].DrawTableRow();
                    }
                }

                UI::EndTable();
            }
        }
        UI::EndChild();
    }
    UI::End();
    UI::PopStyleColor();
}




void AddSimpleTooltip(const string &in msg) {
    if (UI::IsItemHovered()) {
        UI::SetNextWindowSize(300, -1, UI::Cond::Always);
        UI::BeginTooltip();
        UI::TextWrapped(msg);
        UI::EndTooltip();
    }
}

void Notify(const string &in msg) {
    UI::ShowNotification(Meta::ExecutingPlugin().Name, msg);
    trace("Notified: " + msg);
}

void NotifyError(const string &in msg) {
    warn(msg);
    UI::ShowNotification(Meta::ExecutingPlugin().Name + ": Error", msg, vec4(.9, .3, .1, .3), 15000);
}

void NotifyWarning(const string &in msg) {
    warn(msg);
    UI::ShowNotification(Meta::ExecutingPlugin().Name + ": Warning", msg, vec4(.9, .6, .2, .3), 15000);
}
