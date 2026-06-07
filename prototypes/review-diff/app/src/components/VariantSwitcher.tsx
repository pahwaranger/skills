interface VariantSwitcherProps {
  variants: { key: string; name: string }[]
  current: string
  onChange: (key: string) => void
}

export default function VariantSwitcher({ variants, current, onChange }: VariantSwitcherProps) {
  const idx = variants.findIndex(v => v.key === current)
  const prev = variants[(idx - 1 + variants.length) % variants.length]
  const next = variants[(idx + 1) % variants.length]
  const cur = variants[idx]

  return (
    <div className="proto-switcher">
      <button onClick={() => onChange(prev.key)} title={`← ${prev.name} (←)`}>‹</button>
      <span>{cur.key} — {cur.name}</span>
      <button onClick={() => onChange(next.key)} title={`→ ${next.name} (→)`}>›</button>
    </div>
  )
}
