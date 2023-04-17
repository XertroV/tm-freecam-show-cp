const string PluginIcon = Icons::Search;
const string MenuTitle = "\\$af3" + PluginIcon + "\\$z " + Meta::ExecutingPlugin().Name;

// show the window immediately upon installation
[Setting hidden]
bool ShowWindow = true;

/** Render function called every frame intended only for menu items in `UI`. */
void RenderMenu() {
    if (UI::MenuItem(MenuTitle, "", ShowWindow)) {
        ShowWindow = !ShowWindow;
    }
}

uint lastViewTime = 0;
uint lastViewIndex = 0;
AnimMgr@ CamAnimMgr = AnimMgr(true);

class WaypointInfo {
    vec3 pos;
    uint order;
    string tag;
    // index in MapLandmarks
    uint index;
    string label;
    float dist;

    WaypointInfo(uint index, CGameScriptMapLandmark@ lm) {
        this.index = index;
        pos = lm.Position;
        order = lm.Order;
        tag = lm.Tag;
    }

    void UpdateDistToPlayer() {
        dist = (g_PlayerPos - pos).Length();
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
        UI::SetNextItemWidth(UI::GetContentRegionAvail().x - 10.);
        label = UI::InputText("##cp-label-"+index, label);

        UI::TableNextColumn();
        UI::BeginDisabled(!g_IsInFreeCam);
        if (UI::Button("View##cp-" + index)) {
            startnew(CoroutineFunc(ViewMe));
        }
        UI::EndDisabled();
    }

    float viewExtraYaw = 0.0;
    uint animDuration = 500;
    uint lastAnimStart = 0;

    void ViewMe() {
        if (g_FreeCamControl is null) return;

        auto fc = g_FreeCamControl;
        bool animInstead = index == lastViewIndex && (Time::Now - lastViewTime) < 3000;
        lastViewIndex = index;
        lastViewTime = Time::Now;

        if (!animInstead) {
            fc.m_TargetPos = pos;
            fc.m_TargetIsEnabled = true;
            fc.m_Radius = 40.;
            fc.m_Pitch = 0.8;
            fc.m_Yaw = -0.8 + viewExtraYaw;
            viewExtraYaw += Math::PI / 2.0;
            // allow cam to update
            yield();
            @fc = g_FreeCamControl;
            // copy calculated location so we don't have to worry about doing trig
            fc.m_FreeVal_Loc_Translation = fc.Pos;
            fc.m_TargetIsEnabled = false;
        } else {
            @CamAnimMgr = AnimMgr(false, animDuration);
            g_FreeCamControl.m_TargetPos = pos;
            g_FreeCamControl.m_TargetIsEnabled = true;
            auto origYaw = fc.m_Yaw;
            auto newYaw = origYaw + Math::PI / 2.;
            viewExtraYaw += Math::PI / 2.0;

            auto animStarted = Time::Now;
            lastAnimStart = animStarted;

            while (!CamAnimMgr.IsDone && g_IsInFreeCam) {
                if (lastAnimStart != animStarted) {
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
}

string wpCachedForMapUid;
WaypointInfo@[] waypoints;

void CacheWaypoints(CSmArenaClient@ cp) {
    waypoints.RemoveRange(0, waypoints.Length);
    wpCachedForMapUid = "";

    if (cp is null || cp.Arena is null) return;
    if (cp.Map is null) return;
    if (cp.Arena.MapLandmarks.Length == 0) return;

    wpCachedForMapUid = cp.Map.EdChallengeId;

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
void Render() {
    if (!ShowWindow) return;

    auto app = cast<CGameManiaPlanet>(GetApp());
    auto map = app.RootMap;
    if (map is null) return;
    auto cp = cast<CSmArenaClient>(app.CurrentPlayground);
    if (cp is null || cp.Arena is null) return;

    if (wpCachedForMapUid != map.EdChallengeId) {
        CacheWaypoints(cp);
    }

    vec2 size = vec2(450, 300);
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

        if (UI::BeginChild("cp child")) {
            if(UI::BeginTable("cp-table", 6, UI::TableFlags::SizingFixedFit)) {
                UI::TableSetupColumn("#", UI::TableColumnFlags::WidthFixed, 30.);
                UI::TableSetupColumn("Type", UI::TableColumnFlags::WidthFixed, 140.);
                UI::TableSetupColumn("##Order", UI::TableColumnFlags::WidthFixed, 30.);
                UI::TableSetupColumn("Dist", UI::TableColumnFlags::WidthFixed, 60.);
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
