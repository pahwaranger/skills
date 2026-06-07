// Variant C — Three Column + Sidebar Action Header
//
// Structure: 3-column layout (sidebar 200 px | file-tree 160 px | diff pane flex-1)
// Sidebar:  sticky action header at the very top — 3-state toggle button,
//           Update N, Skip N — always visible without scrolling.
//           Below the header: grouped skill list with checkboxes.
// File tree: the second column shows the currently selected skill's files.
//            Clicking a file name smooth-scrolls the diff pane to that section.
//            Split ⇔ / Unified ≡ toggle lives here (compact icon buttons).
// Diff pane: minimal chrome — each file section has a small sticky label
//            (marker + name) but no file-action buttons. Actions happen
//            exclusively via the sidebar header.
// Open question: does the extra column feel like useful context or visual clutter?

import { useRef } from 'react'
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

export default function VariantC({
  skills, selectedSkill, setSelectedSkill,
  checkedSkills, setCheckedSkills,
  diffView, setDiffView,
  onUpdate, onSkip,
}: ReviewProps) {
  // Refs for each file section — used for smooth-scroll from the file tree
  const sectionRefs = useRef<Record<string, HTMLDivElement | null>>({})

  const actionable   = skills.filter(s => s.state !== 'uptodate')
  const selected     = skills.find(s => s.id === selectedSkill)
  const mode         = selectMode(checkedSkills, skills)
  const checkedCount = actionable.filter(s => checkedSkills.has(s.id)).length

  function toggleCheck(id: string) {
    const next = new Set(checkedSkills)
    if (next.has(id)) next.delete(id)
    else              next.add(id)
    setCheckedSkills(next)
  }

  function scrollTo(filename: string) {
    sectionRefs.current[filename]?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }

  const selectIcon  = mode === 'all' ? '☑' : mode === 'new' ? '⊟' : '☐'
  const selectTitle = mode === 'all' ? 'Select new only' : mode === 'new' ? 'Deselect all' : 'Select all'

  const groups = GROUP_ORDER
    .map(state => ({ state, label: GROUP_LABEL[state], items: skills.filter(s => s.state === state) }))
    .filter(g => g.items.length > 0)

  return (
    <div className="vc-layout">

      {/* ── Sidebar ──────────────────────────────────────────── */}
      <div className="vc-sidebar">

        {/* Sticky action header — 3-state toggle + Update N + Skip N */}
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

        {/* Skill list */}
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
                      isSelected    ? 'vc-skill-row--selected'  : '',
                      !isActionable ? 'vc-skill-row--disabled'  : '',
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

      {/* ── File tree ────────────────────────────────────────── */}
      <div className="vc-file-tree">
        <div className="vc-tree-header">
          <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {selected?.label ?? '—'}
          </span>
          {/* Compact split/unified toggle */}
          <div className="segmented">
            <button
              className={diffView === 'split'   ? 'sel' : ''}
              onClick={() => setDiffView('split')}
              title="Split view"
              style={{ fontSize: 11, padding: '2px 9px' }}
            >⇔</button>
            <button
              className={diffView === 'unified' ? 'sel' : ''}
              onClick={() => setDiffView('unified')}
              title="Unified view"
              style={{ fontSize: 11, padding: '2px 9px' }}
            >≡</button>
          </div>
        </div>
        {selected?.files.map(f => (
          <div
            key={f.filename}
            className={`vc-tree-file vc-tree-file--${f.status}`}
            onClick={() => scrollTo(f.filename)}
            title={f.shortName}
          >
            <span className="vc-tree-file-icon">
              {f.status === 'added' ? '+' : f.status === 'deleted' ? '−' : '~'}
            </span>
            <span className="vc-tree-file-name">{f.shortName}</span>
          </div>
        ))}
      </div>

      {/* ── Diff pane ────────────────────────────────────────── */}
      <div className="vc-diff-pane">
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
            <div
              key={f.filename}
              ref={el => { sectionRefs.current[f.filename] = el }}
              className="vc-diff-section"
            >
              {/* Minimal sticky file label */}
              <div className="vc-diff-file-label">
                <span className={`vc-file-marker vc-file-marker--${f.status}`}>
                  {f.status === 'added' ? '+' : f.status === 'deleted' ? '−' : '~'}
                </span>
                <span>{f.shortName}</span>
              </div>
              <div style={{ overflowX: 'auto' }}>
                <DiffRenderer rawDiff={f.rawDiff} view={diffView} />
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  )
}
