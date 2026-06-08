// Variant A — Flat Scroll + Persistent Footer
//
// Structure: 2-column layout (sidebar 220 px | diff pane flex-1)
// Sidebar: state groups with section headers, checkboxes per row,
//          coloured dot on the right for quick state-at-a-glance.
//          Row hover reveals per-skill Update / Skip buttons.
// Main:    continuous stacked file diffs; each file has its own
//          sticky header (filename + status pill + Update/Skip).
// Footer:  persistent bar with 3-state select toggle + bulk actions.
// Open question: does flat-scroll + always-visible footer feel heavy
//                or reassuring?

import type { ReviewProps } from '../App'
import type { Skill } from '../data'
import DiffRenderer from '../components/DiffRenderer'

const STATE_COLOR: Record<string, string> = {
  removed:  'var(--state-removed)',
  update:   'var(--state-update)',
  skipped:  'var(--state-skipped)',
  uptodate: 'var(--state-uptodate)',
}

// Derive which "select mode" we're in from the current checked set.
function selectMode(checked: Set<string>, skills: Skill[]): 'none' | 'all' | 'new' | 'partial' {
  const actionable = skills.filter(s => s.state !== 'uptodate')
  const newOnly    = skills.filter(s => s.state === 'update' || s.state === 'removed')
  if (actionable.length === 0) return 'none'
  const ca = actionable.filter(s => checked.has(s.id)).length
  if (ca === 0) return 'none'
  if (ca === actionable.length) return 'all'
  const cn = newOnly.filter(s => checked.has(s.id)).length
  if (cn === newOnly.length && ca === newOnly.length) return 'new'
  return 'partial'
}

// Return the next checked set when the 3-state toggle is clicked.
function cycleChecked(mode: 'none' | 'all' | 'new' | 'partial', skills: Skill[]): Set<string> {
  const actionable = skills.filter(s => s.state !== 'uptodate')
  const newOnly    = skills.filter(s => s.state === 'update' || s.state === 'removed')
  if (mode === 'none' || mode === 'partial')
    return new Set(actionable.map(s => s.id))
  if (mode === 'all')
    return new Set(newOnly.map(s => s.id))
  return new Set()
}

// Groups for the sidebar (priority order, alphabetical within).
const GROUP_ORDER = ['removed', 'update', 'skipped', 'uptodate'] as const
const GROUP_LABEL: Record<string, string> = {
  removed:  'Removed on origin',
  update:   'Update available',
  skipped:  'Skipped',
  uptodate: 'Up-to-date',
}

export default function VariantA({
  skills, selectedSkill, setSelectedSkill,
  checkedSkills, setCheckedSkills,
  diffView, setDiffView,
  onUpdate, onSkip,
}: ReviewProps) {
  const actionable = skills.filter(s => s.state !== 'uptodate')
  const selected   = skills.find(s => s.id === selectedSkill)
  const mode       = selectMode(checkedSkills, skills)
  const checkedCount = actionable.filter(s => checkedSkills.has(s.id)).length

  function toggleCheck(id: string, checked: boolean) {
    const next = new Set(checkedSkills)
    if (checked) next.add(id)
    else next.delete(id)
    setCheckedSkills(next)
  }

  const selectIcon  = mode === 'all' ? '☑' : mode === 'new' ? '⊟' : '☐'
  const selectLabel = mode === 'all' ? 'Select new only' : mode === 'new' ? 'Deselect all' : 'Select all'

  const groups = GROUP_ORDER
    .map(state => ({ state, label: GROUP_LABEL[state], items: skills.filter(s => s.state === state) }))
    .filter(g => g.items.length > 0)

  return (
    <div className="va-layout">

      {/* ── Sidebar ──────────────────────────────────────────── */}
      <div className="va-sidebar">
        {groups.map(g => (
          <div key={g.state}>
            <div
              className="va-section-header"
              style={{ borderLeftColor: STATE_COLOR[g.state] }}
            >
              {g.label}
            </div>
            {g.items.map(skill => {
              const isActionable = skill.state !== 'uptodate'
              const isSelected   = selectedSkill === skill.id
              const isChecked    = checkedSkills.has(skill.id)
              return (
                <div
                  key={skill.id}
                  className={[
                    'va-skill-row',
                    isSelected   ? 'va-skill-row--selected'  : '',
                    !isActionable ? 'va-skill-row--disabled' : '',
                  ].join(' ')}
                  onClick={() => setSelectedSkill(skill.id)}
                >
                  {isActionable ? (
                    <input
                      type="checkbox"
                      className="skill-checkbox"
                      checked={isChecked}
                      onChange={e => { e.stopPropagation(); toggleCheck(skill.id, e.target.checked) }}
                      onClick={e => e.stopPropagation()}
                    />
                  ) : (
                    <span style={{ width: 15, flexShrink: 0 }} />
                  )}
                  <span className="va-skill-name">{skill.label}</span>
                  <span className="va-state-dot" style={{ background: STATE_COLOR[skill.state] }} />
                  {/* row-level actions revealed on hover */}
                  {isActionable && (
                    <div className="va-row-actions">
                      <button className="va-row-action-sm" onClick={e => { e.stopPropagation(); onUpdate([skill.id]) }}>Update</button>
                      <button className="va-row-action-sm" onClick={e => { e.stopPropagation(); onSkip([skill.id]) }}>Skip</button>
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        ))}
      </div>

      {/* ── Main pane ────────────────────────────────────────── */}
      <div className="va-main">

        {/* Pane header: skill name + Split/Unified toggle */}
        <div className="va-pane-header">
          <span style={{ fontWeight: 600, fontSize: 13 }}>
            {selected?.label ?? '—'}
          </span>
          <div style={{ flex: 1 }} />
          <div className="segmented">
            <button className={diffView === 'split'   ? 'sel' : ''} onClick={() => setDiffView('split')}>Split</button>
            <button className={diffView === 'unified' ? 'sel' : ''} onClick={() => setDiffView('unified')}>Unified</button>
          </div>
        </div>

        {/* Scrolling diff area */}
        <div className="va-diff-scroll">
          {actionable.length === 0 ? (
            <div className="caught-up">
              <span className="caught-up-icon">✓</span>
              <p>All caught up!</p>
              <span>Nothing left to review.</span>
            </div>
          ) : selected?.state === 'uptodate' ? (
            <div className="caught-up">
              <span className="caught-up-icon">✓</span>
              <p>Up to date</p>
              <span>Nothing to sync for this skill.</span>
              <a
                href={`https://github.com/pahwaranger/skills/tree/main/skills/${selected.id}`}
                target="_blank" rel="noreferrer"
              >
                View on GitHub ↗
              </a>
            </div>
          ) : (
            selected?.files.map(f => (
              <div key={f.filename} className="va-file-section">
                <div className="va-file-header">
                  <span className="va-filename">{f.shortName}</span>
                  <span className={`va-status-pill va-status-${f.status}`}>
                    {f.status.charAt(0).toUpperCase() + f.status.slice(1)}
                  </span>
                  <div style={{ flex: 1 }} />
                  <button className="va-row-btn" onClick={() => selected && onUpdate([selected.id])}>Update</button>
                  <button className="va-row-btn" onClick={() => selected && onSkip([selected.id])}>Skip</button>
                </div>
                <div style={{ overflowX: 'auto' }}>
                  <DiffRenderer rawDiff={f.rawDiff} view={diffView} />
                </div>
              </div>
            ))
          )}
        </div>

        {/* Persistent footer bar */}
        {actionable.length > 0 && (
          <div className="va-footer">
            <button className="va-select-toggle" onClick={() => setCheckedSkills(cycleChecked(mode, skills))}>
              <span className="va-toggle-icon">{selectIcon}</span>
              {selectLabel}
            </button>
            <div style={{ flex: 1 }} />
            <button
              className="va-action-btn va-action-secondary"
              disabled={checkedCount === 0}
              onClick={() => onSkip([...checkedSkills])}
            >
              Skip selected{checkedCount > 0 ? ` (${checkedCount})` : ''}
            </button>
            <button
              className="va-action-btn va-action-primary"
              disabled={checkedCount === 0}
              onClick={() => onUpdate([...checkedSkills])}
            >
              Update selected{checkedCount > 0 ? ` (${checkedCount})` : ''}
            </button>
          </div>
        )}
      </div>
    </div>
  )
}
