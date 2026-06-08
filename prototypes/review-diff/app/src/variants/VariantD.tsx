// Variant D — C's sidebar × B's main pane
//
// Sidebar (from C): sticky action header at top — 3-state toggle,
//   Update N, Skip N — always visible without scrolling. Compact
//   grouped skill list with checkboxes below.
// Main pane (from B): collapsible file cards with line counts.
//   The materialising toolbar still appears when skills are checked,
//   giving a second, in-context action surface.
//
// Open question: with bulk actions already pinned in the sidebar header,
// does the toolbar feel redundant or helpfully close to the diff content?

import { useState } from 'react'
import type { ReviewProps } from '../App'
import type { Skill } from '../data'
import DiffRenderer from '../components/DiffRenderer'

const STATE_COLOR: Record<string, string> = {
  removed:  'var(--state-removed)',
  update:   'var(--state-update)',
  skipped:  'var(--state-skipped)',
  uptodate: 'var(--state-uptodate)',
}
const GROUP_ORDER = ['removed', 'update', 'skipped', 'uptodate'] as const
const GROUP_LABEL: Record<string, string> = {
  removed:  'Removed',
  update:   'Updates',
  skipped:  'Skipped',
  uptodate: 'Up to date',
}
const STATE_BADGE: Record<string, string> = {
  removed:  'Removed',
  update:   'Update',
  skipped:  'Skipped',
  uptodate: 'Up to date',
}

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

function cycleChecked(mode: 'none' | 'all' | 'new' | 'partial', skills: Skill[]): Set<string> {
  const actionable = skills.filter(s => s.state !== 'uptodate')
  const newOnly    = skills.filter(s => s.state === 'update' || s.state === 'removed')
  if (mode === 'none' || mode === 'partial') return new Set(actionable.map(s => s.id))
  if (mode === 'all')                        return new Set(newOnly.map(s => s.id))
  return new Set()
}

function countLines(rawDiff: string) {
  return {
    added:   (rawDiff.match(/^\+[^+]/gm) ?? []).length,
    removed: (rawDiff.match(/^-[^-]/gm)  ?? []).length,
  }
}

export default function VariantD({
  skills, selectedSkill, setSelectedSkill,
  checkedSkills, setCheckedSkills,
  diffView, setDiffView,
  onUpdate, onSkip,
}: ReviewProps) {
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set())

  const actionable   = skills.filter(s => s.state !== 'uptodate')
  const selected     = skills.find(s => s.id === selectedSkill)
  const mode         = selectMode(checkedSkills, skills)
  const checkedCount = actionable.filter(s => checkedSkills.has(s.id)).length
  const showToolbar  = checkedCount > 0

  function toggleCheck(id: string) {
    const next = new Set(checkedSkills)
    if (next.has(id)) next.delete(id)
    else              next.add(id)
    setCheckedSkills(next)
  }

  function toggleFile(filename: string) {
    const next = new Set(collapsed)
    if (next.has(filename)) next.delete(filename)
    else                    next.add(filename)
    setCollapsed(next)
  }

  const selectIcon  = mode === 'all' ? '☑' : mode === 'new' ? '⊟' : '☐'
  const selectTitle = mode === 'all' ? 'Select new only' : mode === 'new' ? 'Deselect all' : 'Select all'
  const toolbarIcon = mode === 'all' ? '☑' : mode === 'new' ? '⊟' : '☑'

  const groups = GROUP_ORDER
    .map(state => ({ state, label: GROUP_LABEL[state], items: skills.filter(s => s.state === state) }))
    .filter(g => g.items.length > 0)

  return (
    <div style={{ display: 'flex', height: '100%', overflow: 'hidden' }}>

      {/* ── Sidebar (Variant C style) ─────────────────────── */}
      <div className="vc-sidebar">

        {/* Sticky action header — always visible */}
        <div className="vc-action-header">
          <button
            className="vc-select-toggle"
            onClick={() => setCheckedSkills(cycleChecked(mode, skills))}
            title={selectTitle}
          >
            {selectIcon}
          </button>
          <button
            className="vc-action-btn"
            disabled={checkedCount === 0}
            onClick={() => onUpdate([...checkedSkills])}
          >
            Update{checkedCount > 0 ? ` ${checkedCount}` : ''}
          </button>
          <button
            className="vc-action-btn vc-action-btn--secondary"
            disabled={checkedCount === 0}
            onClick={() => onSkip([...checkedSkills])}
          >
            Skip{checkedCount > 0 ? ` ${checkedCount}` : ''}
          </button>
        </div>

        {/* Grouped skill list */}
        <div className="vc-skill-list">
          {groups.map(g => (
            <div key={g.state}>
              <div className="vc-group-header" style={{ color: STATE_COLOR[g.state] }}>
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
                      'vc-skill-row',
                      isSelected    ? 'vc-skill-row--selected' : '',
                      !isActionable ? 'vc-skill-row--disabled' : '',
                    ].join(' ')}
                    onClick={() => setSelectedSkill(skill.id)}
                  >
                    {isActionable ? (
                      <input
                        type="checkbox"
                        className="skill-checkbox"
                        checked={isChecked}
                        onChange={() => toggleCheck(skill.id)}
                        onClick={e => e.stopPropagation()}
                      />
                    ) : (
                      <span style={{ width: 15, flexShrink: 0 }} />
                    )}
                    <span className="vc-skill-label">{skill.label}</span>
                  </div>
                )
              })}
            </div>
          ))}
        </div>
      </div>

      {/* ── Main pane (Variant B style) ──────────────────── */}
      <div className="vb-main">

        {/* Materialising toolbar — appears on first check */}
        {showToolbar && (
          <div className="vb-toolbar">
            <button
              className="vb-select-cycle"
              onClick={() => setCheckedSkills(cycleChecked(mode, skills))}
              title={selectTitle}
            >
              {toolbarIcon}
            </button>
            <span>{checkedCount} selected</span>
            <div style={{ flex: 1 }} />
            <button className="vb-toolbar-btn" onClick={() => onSkip([...checkedSkills])}>Skip</button>
            <button className="vb-toolbar-btn vb-toolbar-btn--primary" onClick={() => onUpdate([...checkedSkills])}>Update</button>
            <button
              className="vb-toolbar-dismiss"
              onClick={() => setCheckedSkills(new Set())}
              title="Clear selection"
            >✕</button>
          </div>
        )}

        {/* Pane header: skill name + state chip + Split/Unified */}
        <div className="vb-pane-header">
          <span style={{ fontWeight: 600, fontSize: 13 }}>{selected?.label ?? '—'}</span>
          {selected && selected.state !== 'uptodate' && (
            <span
              className="vb-state-chip"
              style={{ background: STATE_COLOR[selected.state] }}
            >
              {STATE_BADGE[selected.state]}
            </span>
          )}
          <div style={{ flex: 1 }} />
          <div className="segmented">
            <button className={diffView === 'split'   ? 'sel' : ''} onClick={() => setDiffView('split')}>Split</button>
            <button className={diffView === 'unified' ? 'sel' : ''} onClick={() => setDiffView('unified')}>Unified</button>
          </div>
        </div>

        {/* Collapsible file cards */}
        <div className="vb-diff-scroll">
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
                href={`https://github.com/pahwaranger/skills/tree/master/skills/${selected.id}`}
                target="_blank" rel="noreferrer"
              >
                View on GitHub ↗
              </a>
            </div>
          ) : (
            selected?.files.map(f => {
              const isCollapsed = collapsed.has(f.filename)
              const { added, removed } = countLines(f.rawDiff)
              return (
                <div key={f.filename} className="vb-file-card">
                  <div
                    className="vb-file-card-header"
                    onClick={() => toggleFile(f.filename)}
                  >
                    <span className="vb-chevron">{isCollapsed ? '▶' : '▼'}</span>
                    <span className="vb-file-card-name">{f.shortName}</span>
                    <span className={`vb-file-status vb-file-status--${f.status}`}>
                      {f.status.charAt(0).toUpperCase() + f.status.slice(1)}
                    </span>
                    {added   > 0 && <span className="vb-lines-added">+{added}</span>}
                    {removed > 0 && <span className="vb-lines-removed">−{removed}</span>}
                  </div>
                  {!isCollapsed && (
                    <div className="vb-file-card-body">
                      <DiffRenderer rawDiff={f.rawDiff} view={diffView} />
                    </div>
                  )}
                </div>
              )
            })
          )}
        </div>
      </div>
    </div>
  )
}
