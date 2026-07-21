// OBTrack main screen — before Start, settings panel expanded.
// Mirrors ContentView.swift portraitLayout: topBar + settingsPanel +
// placeholder camera + statusPanel + liveDataPanel + visualTogglePanel +
// controlButtons (Start/Stop + Live Trim).
import {
  C, Lockup, ReticleMark, StateDot, Panel, Row, DataField, IOSToggle,
  PhoneChrome,
} from "./_shared/obtrack";
import { Crosshair, ChevronUp, Layers, Box, RadioTower, StopCircle, SlidersHorizontal } from "lucide-react";

export function MainIdle() {
  return (
    <PhoneChrome>
      {/* top bar (ultraThinMaterial) */}
      <div className="z-10 flex items-center justify-between bg-white/10 px-4 py-2.5 backdrop-blur-xl">
        <Lockup markSize={24} />
        <div className="flex items-center gap-3">
          <StateDot state="notAvailable" />
          <Crosshair className="h-5 w-5 text-white" />
          <ChevronUp className="h-5 w-5 rounded-full text-white" />
        </div>
      </div>

      {/* settings panel — ALL network settings present */}
      <div className="z-10 bg-white/10 px-3 pt-2 pb-2 backdrop-blur-xl">
        <Panel>
          <div className="mb-2 text-[11px] font-bold text-white/70">⌁ Network</div>
          <div className="flex gap-2">
            <div className="flex-1">
              <div className="mb-0.5 text-[10px] text-white/60">IP</div>
              <div className="rounded-md border border-white/20 bg-white/90 px-2 py-1.5 text-[11px] text-black">
                192.168.1.100
              </div>
            </div>
            <div className="w-16">
              <div className="mb-0.5 text-[10px] text-white/60">Port</div>
              <div className="rounded-md border border-white/20 bg-white/90 px-2 py-1.5 text-[11px] text-black">
                5005
              </div>
            </div>
            <div className="w-20">
              <div className="mb-0.5 text-[10px] text-white/60">Rate</div>
              <div className="flex overflow-hidden rounded-md bg-white/20 text-[11px]">
                <div className="flex-1 bg-white/90 py-1.5 text-center font-semibold text-black">30</div>
                <div className="flex-1 py-1.5 text-center text-white">60</div>
              </div>
            </div>
          </div>
          <div className="mt-3 flex items-center justify-between">
            <div>
              <div className="text-[11px] text-white">Lite (shooting) mode</div>
              <div className="text-[10px] text-white/55">
                No mesh, no depth — pose only. Use for long takes.
              </div>
            </div>
            <IOSToggle on={false} />
          </div>
        </Panel>
      </div>

      {/* placeholder camera area */}
      <div className="flex flex-1 flex-col items-center justify-center gap-4">
        <ReticleMark size={84} />
        <Lockup markSize={26} tagline />
        <div className="pt-2 text-[14px] text-white/45">Camera starts with tracking</div>
      </div>

      {/* bottom stack */}
      <div className="z-10 space-y-2.5 bg-white/10 p-3 backdrop-blur-xl">
        <Panel>
          <Row label="Status"><StateDot state="notAvailable" /></Row>
          <Row label="UDP"><span className="font-mono text-[11px] text-white/80">Idle</span></Row>
          <Row label="Frames"><span className="font-mono text-[11px] text-white/80">0</span></Row>
          <Row label="Profile"><span className="font-mono text-[11px] text-white/60">raw (no calibration)</span></Row>
        </Panel>

        <Panel>
          <div className="mb-1 text-[11px] text-white/60">Position (m)</div>
          <div className="flex gap-2">
            <DataField label="X" value="0.000" />
            <DataField label="Y" value="0.000" />
            <DataField label="Z" value="0.000" />
          </div>
          <div className="my-2 h-px bg-white/20" />
          <div className="mb-1 text-[11px] text-white/60">Quaternion</div>
          <div className="flex gap-1">
            <DataField label="QX" value="0.000" />
            <DataField label="QY" value="0.000" />
            <DataField label="QZ" value="0.000" />
            <DataField label="QW" value="1.000" />
          </div>
        </Panel>

        {/* Depth / Mesh toggles */}
        <div className="flex justify-center gap-2.5">
          <div className="flex items-center gap-1.5 rounded-lg bg-orange-500/80 px-3 py-1.5 text-[11px] text-white">
            <Layers className="h-3.5 w-3.5" /> Depth
          </div>
          <div className="flex items-center gap-1.5 rounded-lg bg-cyan-500/80 px-3 py-1.5 text-[11px] text-white">
            <Box className="h-3.5 w-3.5" /> Mesh
          </div>
        </div>

        {/* Start / Stop + Live Trim */}
        <div className="space-y-2">
          <div className="flex gap-2.5">
            <div className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-green-500 py-2.5 text-[14px] font-bold text-white">
              <RadioTower className="h-4 w-4" /> Start
            </div>
            <div className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-red-500/40 py-2.5 text-[14px] font-bold text-white/50">
              <StopCircle className="h-4 w-4" /> Stop
            </div>
          </div>
          <div className="flex items-center justify-center gap-1.5 rounded-xl border border-white/30 bg-white/10 py-2 text-[14px] font-bold text-white">
            <SlidersHorizontal className="h-4 w-4" /> Live Trim
          </div>
        </div>
      </div>
    </PhoneChrome>
  );
}
