/**
 * Y-axis label drawn inside the plot at its right edge, just above its
 * gridline, so charts need no empty gutter for the axis.
 */
export function InsideTick({ x, y, payload, format }: { x?: number | string; y?: number | string; payload?: { value: number }; format: (v: number) => string }) {
  if (payload === undefined) return null;
  return (
    <text x={Number(x) - 14} y={Number(y) - 6} textAnchor="end" fill="var(--subtle)" fontSize={11} className="tabular" stroke="var(--surface)" strokeWidth={3} paintOrder="stroke" strokeLinejoin="round">
      {format(payload.value)}
    </text>
  );
}
