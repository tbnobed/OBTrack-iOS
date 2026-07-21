// OBTrack main screen — while tracking. Settings auto-collapse on Start
// (tap the gear/chevron to re-open them); status is live, Stop is enabled,
// and Live Trim stays available for mid-take adjustments.
import {
  C, Lockup, StateDot, Panel, Row, DataField, PhoneChrome,
} from "./_shared/obtrack";
import { Crosshair, Settings, Layers, Box, RadioTower, StopCircle, SlidersHorizontal } from "lucide-react";

export function MainTracking() {
  return (
    <PhoneChrome>
      {/* top bar — gear icon means settings are collapsed, tap to expand */}
      <div className="z-10 flex items-center justify-between bg-white/10 px-4 py-2.5 backdrop-blur-xl">
        <Lockup markSize={24} />
        <div className="flex items-center gap-3">
          <StateDot state="normal" />
          <Crosshair className="h-5 w-5" style={{ color: C.accent }} />
          <Settings className="h-5 w-5 text-white" />
        </div>
      </div>

      {/* simulated live camera feed */}
      <div className="relative flex-1 overflow-hidden">
        <div className="absolute inset-0"
          style={{
            background:
              "radial-gradient(120% 90% at 30% 20%, #3b4a63 0%, #22304a 40%, #131c30 75%, #0B1220 100%)",
          }} />
        {/* faint LiDAR mesh wireframe suggestion */}
        <svg className="absolute inset-0 h-full w-full opacity-25" viewBox="0 0 390 500">
          {Array.from({ length: 9 }).map((_, i) => (
            <path key={`h${i}`} d={`M0 ${60 + i * 50} Q 195 ${40 + i * 52} 390 ${65 + i * 48}`}
              stroke="#67e8f9" strokeWidth="0.7" fill="none" />
          ))}
          {Array.from({ length: 11 }).map((_, i) => (
            <path key={`v${i}`} d={`M${i * 39} 0 Q ${i * 39 + 10} 250 ${i * 39 - 5} 500`}
              stroke="#67e8f9" strokeWidth="0.7" fill="none" />
          ))}
        </svg>
        <div className="absolute left-3 top-3 rounded bg-black/40 px-2 py-1 font-mono text-[10px] text-cyan-300">
          LiDAR mesh · depth 10 fps
        </div>
      </div>

      {/* bottom stack */}
      <div className="z-10 space-y-2.5 bg-white/10 p-3 backdrop-blur-xl">
        <Panel>
          <Row label="Status"><StateDot state="normal" /></Row>
          <Row label="UDP"><span className="font-mono text-[11px] text-white/80">Sending → 192.168.1.100:5005</span></Row>
          <Row label="Frames"><span className="font-mono text-[11px] text-white/80">12 847</span></Row>
          <Row label="Profile"><span className="font-mono text-[11px]" style={{ color: C.accent }}>StageA-50mm</span></Row>
        </Panel>

        <Panel>
          <div className="mb-1 text-[11px] text-white/60">Position (m)</div>
          <div className="flex gap-2">
            <DataField label="X" value="1.482" />
            <DataField label="Y" value="1.203" />
            <DataField label="Z" value="-0.874" />
          </div>
          <div className="my-2 h-px bg-white/20" />
          <div className="mb-1 text-[11px] text-white/60">Quaternion</div>
          <div className="flex gap-1">
            <DataField label="QX" value="0.021" />
            <DataField label="QY" value="0.383" />
            <DataField label="QZ" value="-0.014" />
            <DataField label="QW" value="0.924" />
          </div>
        </Panel>

        <div className="flex justify-center gap-2.5">
          <div className="flex items-center gap-1.5 rounded-lg bg-orange-500 px-3 py-1.5 text-[11px] text-white">
            <Layers className="h-3.5 w-3.5" /> Depth
          </div>
          <div className="flex items-center gap-1.5 rounded-lg bg-cyan-500 px-3 py-1.5 text-[11px] text-white">
            <Box className="h-3.5 w-3.5" /> Mesh
          </div>
        </div>

        <div className="space-y-2">
          <div className="flex gap-2.5">
            <div className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-green-500/40 py-2.5 text-[14px] font-bold text-white/50">
              <RadioTower className="h-4 w-4" /> Start
            </div>
            <div className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-red-500 py-2.5 text-[14px] font-bold text-white">
              <StopCircle className="h-4 w-4" /> Stop
            </div>
          </div>
          {/* Live Trim stays tappable while streaming; accent = trim active */}
          <div className="flex items-center justify-center gap-1.5 rounded-xl border py-2 text-[14px] font-bold"
            style={{ borderColor: C.accent, color: C.accent, background: "rgba(56,189,248,0.12)" }}>
            <SlidersHorizontal className="h-4 w-4" /> Live Trim — active
          </div>
        </div>
      </div>
    </PhoneChrome>
  );
}
