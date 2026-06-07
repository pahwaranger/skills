// Variant B — Collapsible Files + Appears-on-check Toolbar
//
// Structure: 2-column layout (sidebar 220 px | diff pane flex-1)
// Sidebar: compact rows, state encoded via left accent border + small
//          badge text. No section header labels — visual weight moves
//          to the border colour.
// Main:    each file is a collapsible card (open by default). GitHub
//          "Files changed" style: clicking the header collapses/expands.
//          Line counts (+N / -N) visible in the card header.
// Toolbar: a sticky selection toolbar materialises at the top of the
//          diff pane the moment any skill is checked. Contains the
//          3-state toggle (as an indeterminate-style checkbox), count
//          text, Update + Skip buttons, and a ✕ to dismiss.
// Open question: does the appearing toolbar feel like a helpful signal
//                or a surprising jolt?

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
const STATE_BADGE: Record<string, string> = {
  removed:  'Removed',
  update:   'Update',
  skipped:  'Skipped',
  uptodate: 'Current',
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

// Count +/- lines in a raw diff string for the card header
function countLines(rawDiff: string) {
  const added   = (rawDiff.match(/^\+[^+]/gm) ?? []).length
  const removed = (rawDiff.match(/^-[^-]/gm)  ?? []).length
  return { added, removed }
}

export default function VariantB({
  skills, selectedSkill, setSelectedSkill,
  checkedSkills, setCheckedSkills,
  diffView, setDiffView,
  onUpdate, onSkip,
}: ReviewProps) {
  // Track which file cards are collapsed (start all open)
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

  // The 3-state toggle icon in the toolbar
  const toggleIcon =
    mode === 'all'  ? '☑' :
    mode === 'new'  ? '⊟' : '☑'

  // Sidebar: sorted by state priority, alpha within group
  const sorted = [...skills].sort((a, b) => {
    const order = { removed: 0, update: 1, skipped: 2, uptodate: 3 }
    const diff = order[a.state] - order[b.state]
    return diff !== 0 ? diff : a.label.localeCompare(b.label)
  })

  return (
    <div className="vb-layout">

      {/* ── Sidebar ──────────────────────────────────────────── */}
      <div className="vb-sidebar">
        <div className="vb-sidebar-title">Skills</div>
        {sorted.map(skill => {
          const isActionable = skill.state !== 'uptodate'
          const isSelected   = selectedSkill === skill.id
          const isChecked    = checkedSkills.has(skill.id)
          return (
            <div
              key={skill.id}
              className={[
                'vb-skill-row',
                isSelected    ? 'vb-skill-row--selected'  : '',
                !isActionable ? 'vb-skill-row--disabled'  : '',
              ].join(' ')}
              style={{ borderLeftColor: STATE_COLOR[skill.state] }}
              onClick={() => setSelectedSkill(skill.id)}
            >
              {isActionable && (
                <input
                  type="checkbox"
                  className="skill-checkbox"
                  checked={isChecked}
                  onChange={() => toggleCheck(skill.id)}
                  onClick={e => e.stopPropagation()}
                />
              )}
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="vb-skill-label">{skill.label}</div>
                <div className="vb-skill-badge" style={{ color: STATE_COLOR[skill.state] }}>
                  {STATE_BADGE[skill.state]}
                </div>
              </div>
            </div>
          )
        })}
      </div>

      {/* ── Main pane ────────────────────────────────────────── */}
      <div className="vb-main">

        {/* Floating toolbar — appears when ≥1 skill is checked */}
        {showToolbar && (
          <div className="vb-toolbar">
            {/* 3-state toggle */}
            <button
              className="vb-select-cycle"
              onClick={() => setCheckedSkills(cycleChecked(mode, skills))}
              title={mode === 'all' ? 'Switch to new-only' : mode === 'new' ? 'Deselect all' : 'Select all'}
            >
              {toggleIcon}
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

        {/* Scrolling diff area with collapsible file cards */}
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
                href={`https://github.com/pahwaranger/skills/tree/main/skills/${selected.id}`}
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
                  {/* Card header — click to collapse/expand */}
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
                  {/* Expanded body */}
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
