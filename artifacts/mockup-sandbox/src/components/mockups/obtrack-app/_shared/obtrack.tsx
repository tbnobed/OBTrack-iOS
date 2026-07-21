// Faithful web replicas of the OBTrack iOS SwiftUI components.
// Colors from BrandMark.swift: accent #38BDF8, accentDeep #2563EB,
// inkLight #E8EEF6, inkDark #0B1220.

export const C = {
  accent: "#38BDF8",
  accentDeep: "#2563EB",
  inkLight: "#E8EEF6",
  inkDark: "#0B1220",
};

export function ReticleMark({ size = 24 }: { size?: number }) {
  const s = size;
  const stroke = Math.max(1.5, s * 0.07);
  const b = s * 0.16; // bracket arm length
  return (
    <svg width={s} height={s} viewBox="0 0 100 100" fill="none">
      <defs>
        <linearGradient id="obg" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor={C.accent} />
          <stop offset="1" stopColor={C.accentDeep} />
        </linearGradient>
      </defs>
      {/* gradient corner brackets */}
      {[
        `M 8 ${8 + b * 2} L 8 8 L ${8 + b * 2} 8`,
        `M ${92 - b * 2} 8 L 92 8 L 92 ${8 + b * 2}`,
        `M 92 ${92 - b * 2} L 92 92 L ${92 - b * 2} 92`,
        `M ${8 + b * 2} 92 L 8 92 L 8 ${92 - b * 2}`,
      ].map((d, i) => (
        <path key={i} d={d} stroke="url(#obg)" strokeWidth={stroke * 2.2}
          strokeLinecap="round" />
      ))}
      {/* white ring */}
      <circle cx="50" cy="50" r="24" stroke={C.inkLight}
        strokeWidth={stroke * 2} />
      {/* accent dot */}
      <circle cx="50" cy="50" r="8" fill={C.accent} />
    </svg>
  );
}

export function Lockup({ markSize = 24, tagline = false }: { markSize?: number; tagline?: boolean }) {
  return (
    <div className="flex items-center gap-2">
      <ReticleMark size={markSize} />
      <div className="leading-tight">
        <div className="font-semibold tracking-tight"
          style={{ color: C.inkLight, fontSize: markSize * 0.75 }}>
          OB<span style={{ color: C.accent }}>Track</span>
        </div>
        {tagline && (
          <div className="text-[10px] text-white/45">6DOF camera tracking</div>
        )}
      </div>
    </div>
  );
}

export function StateDot({ state }: { state: string }) {
  const color = state === "normal" ? "#4ade80"
    : state.startsWith("limited") ? "#fb923c" : "#f87171";
  return (
    <div className="flex items-center gap-1.5">
      <span className="rounded-full" style={{ width: 9, height: 9, background: color }} />
      <span className="font-mono text-[11px]" style={{ color }}>{state}</span>
    </div>
  );
}

export function Panel({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={`rounded-[10px] bg-black/35 p-2.5 ${className}`}>{children}</div>
  );
}

export function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between py-0.5">
      <span className="text-[11px] text-white/60">{label}</span>
      {children}
    </div>
  );
}

export function DataField({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-1 flex-col items-center gap-0.5">
      <span className="text-[9px] text-white/50">{label}</span>
      <span className="font-mono text-[11px] text-white">{value}</span>
    </div>
  );
}

export function IOSToggle({ on, tint = "#4ade80" }: { on: boolean; tint?: string }) {
  return (
    <div className="relative shrink-0 rounded-full transition-colors"
      style={{ width: 51, height: 31, background: on ? tint : "rgba(120,120,128,0.32)" }}>
      <div className="absolute top-[2px] rounded-full bg-white shadow-md"
        style={{ width: 27, height: 27, left: on ? 22 : 2 }} />
    </div>
  );
}

export function PhoneChrome({ children }: { children: React.ReactNode }) {
  return (
    <div className="relative flex h-screen w-full flex-col overflow-hidden font-sans"
      style={{ background: C.inkDark }}>
      {/* status bar */}
      <div className="z-20 flex items-center justify-between px-8 pt-3 pb-1 text-[13px] font-semibold text-white">
        <span>9:41</span>
        <span className="flex items-center gap-1 text-[11px]">
          <span>●●●</span><span>Wi-Fi</span><span>▮▮▮▯</span>
        </span>
      </div>
      {children}
    </div>
  );
}
