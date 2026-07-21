// The new Live Trim sheet (TrimView.swift) — usable WHILE streaming.
// iOS grouped-form styling: invert rotation, mirror position, cm nudges, reset.
import { IOSToggle } from "./_shared/obtrack";
import { RadioTower, Minus, Plus } from "lucide-react";

function Group({ header, footer, children }: {
  header?: string; footer?: string; children: React.ReactNode;
}) {
  return (
    <div className="px-4 pt-5">
      {header && (
        <div className="mb-1.5 px-3 text-[12px] uppercase tracking-wide text-[#8e8e93]">
          {header}
        </div>
      )}
      <div className="divide-y divide-black/10 rounded-xl bg-white">{children}</div>
      {footer && (
        <div className="mt-1.5 px-3 text-[12px] leading-snug text-[#8e8e93]">{footer}</div>
      )}
    </div>
  );
}

function ToggleRow({ label, on }: { label: string; on: boolean }) {
  return (
    <div className="flex items-center justify-between px-3 py-2.5">
      <span className="text-[15px] text-black">{label}</span>
      <IOSToggle on={on} />
    </div>
  );
}

function StepperRow({ label, value }: { label: string; value: string }) {
  const zero = value === "0 cm";
  return (
    <div className="flex items-center justify-between px-3 py-2">
      <span className="text-[15px] text-black">{label}</span>
      <div className="flex items-center gap-3">
        <span className={`font-mono text-[15px] ${zero ? "text-[#8e8e93]" : "text-black"}`}>
          {value}
        </span>
        <div className="flex overflow-hidden rounded-lg bg-[#e9e9eb]">
          <div className="flex h-8 w-11 items-center justify-center border-r border-black/10">
            <Minus className="h-4 w-4 text-black" />
          </div>
          <div className="flex h-8 w-11 items-center justify-center">
            <Plus className="h-4 w-4 text-black" />
          </div>
        </div>
      </div>
    </div>
  );
}

export function TrimSheet() {
  return (
    <div className="flex h-screen w-full flex-col overflow-hidden bg-[#f2f2f7] font-sans">
      {/* sheet grabber + nav bar */}
      <div className="flex justify-center pt-2">
        <div className="h-1.5 w-10 rounded-full bg-black/20" />
      </div>
      <div className="relative flex items-center justify-center px-4 py-3">
        <span className="text-[17px] font-semibold text-black">Live Trim</span>
        <span className="absolute right-4 text-[17px] font-semibold text-[#007aff]">Done</span>
      </div>

      <div className="flex-1 overflow-y-auto pb-8">
        <Group>
          <div className="flex items-center gap-2 px-3 py-2.5">
            <RadioTower className="h-4 w-4 text-green-600" />
            <span className="text-[12px] text-green-600">
              Streaming — changes apply instantly in Unreal / LiveFX.
            </span>
          </div>
        </Group>

        <Group header="Invert rotation"
          footer="Flip one at a time: yaw the phone left — if the CG camera yaws right, invert pan. Then repeat for tilt and roll.">
          <ToggleRow label="Invert pan (yaw)" on={true} />
          <ToggleRow label="Invert tilt (pitch)" on={false} />
          <ToggleRow label="Invert roll" on={false} />
        </Group>

        <Group header="Mirror position"
          footer="Walk right — if the CG camera moves left, mirror X. Same drill for forward (Y) and up (Z).">
          <ToggleRow label="Mirror X (right / left)" on={false} />
          <ToggleRow label="Mirror Y (forward / back)" on={false} />
          <ToggleRow label="Mirror Z (up / down)" on={false} />
        </Group>

        <Group header="Nudge position (cm)"
          footer="Shifts the reported camera position in the output frame: X = right, Y = forward, Z = up. Applied after mirroring.">
          <StepperRow label="X (right)" value="0 cm" />
          <StepperRow label="Y (forward)" value="25 cm" />
          <StepperRow label="Z (up)" value="0 cm" />
        </Group>

        <Group>
          <div className="px-3 py-2.5 text-center text-[15px] text-[#ff3b30]">
            Reset all trims
          </div>
        </Group>
      </div>
    </div>
  );
}
