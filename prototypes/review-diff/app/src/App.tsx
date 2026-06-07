import { useState, useEffect } from 'react'
import { SKILLS } from './data'
import WindowChrome from './components/WindowChrome'
import VariantSwitcher from './components/VariantSwitcher'
import VariantA from './variants/VariantA'
import VariantB from './variants/VariantB'
import VariantC from './variants/VariantC'
import VariantD from './variants/VariantD'
import type { Skill } from './data'

export type Variant = 'A' | 'B' | 'C' | 'D'
const VARIANTS: Variant[] = ['A', 'B', 'C', 'D']
const VARIANT_NAMES: Record<Variant, string> = {
  A: 'Flat scroll',
  B: 'Collapsible files',
  C: 'Three column',
  D: 'C sidebar + B pane',
}

export interface ReviewProps {
  skills: Skill[]
  selectedSkill: string
  setSelectedSkill: (id: string) => void
  checkedSkills: Set<string>
  setCheckedSkills: (s: Set<string>) => void
  diffView: 'split' | 'unified'
  setDiffView: (v: 'split' | 'unified') => void
  onUpdate: (ids: string[]) => void
  onSkip: (ids: string[]) => void
}

function getInitVariant(): Variant {
  const v = new URLSearchParams(window.location.search).get('variant')?.toUpperCase()
  return VARIANTS.includes(v as Variant) ? (v as Variant) : 'D'
}

export default function App() {
  const [variant, setVariant] = useState<Variant>(getInitVariant)
  const [selectedSkill, setSelectedSkill] = useState('grill-with-docs')
  const [checkedSkills, setCheckedSkills] = useState<Set<string>>(new Set())
  const [resolvedSkills, setResolvedSkills] = useState<Set<string>>(new Set())
  const [diffView, setDiffView] = useState<'split' | 'unified'>('split')

  const visibleSkills = SKILLS.filter(s => !resolvedSkills.has(s.id))

  function changeVariant(v: Variant) {
    setVariant(v)
    const url = new URL(window.location.href)
    url.searchParams.set('variant', v)
    window.history.replaceState({}, '', url.toString())
  }

  function handleAction(ids: string[]) {
    const nextResolved = new Set([...resolvedSkills, ...ids])
    setResolvedSkills(nextResolved)
    // remove resolved from checked
    setCheckedSkills(prev => {
      const s = new Set(prev)
      ids.forEach(id => s.delete(id))
      return s
    })
    // auto-select next actionable if current was resolved
    if (ids.includes(selectedSkill)) {
      const remaining = visibleSkills.filter(
        s => !ids.includes(s.id) && s.state !== 'uptodate'
      )
      const fallback = visibleSkills.find(s => !ids.includes(s.id))
      setSelectedSkill(remaining[0]?.id ?? fallback?.id ?? '')
    }
  }

  // ← / → keys cycle variants (skip when typing in inputs)
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const tag = (e.target as Element)?.tagName
      if (tag === 'INPUT' || tag === 'TEXTAREA') return
      if (e.key === 'ArrowLeft') {
        const i = VARIANTS.indexOf(variant)
        changeVariant(VARIANTS[(i - 1 + VARIANTS.length) % VARIANTS.length])
      } else if (e.key === 'ArrowRight') {
        const i = VARIANTS.indexOf(variant)
        changeVariant(VARIANTS[(i + 1) % VARIANTS.length])
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [variant])

  const props: ReviewProps = {
    skills: visibleSkills,
    selectedSkill,
    setSelectedSkill,
    checkedSkills,
    setCheckedSkills,
    diffView,
    setDiffView,
    onUpdate: handleAction,
    onSkip: handleAction,  // same effect in prototype — both "resolve" the skill
  }

  return (
    <>
      <div className="window">
        <WindowChrome />
        <div className="win-content">
          {variant === 'A' && <VariantA {...props} />}
          {variant === 'B' && <VariantB {...props} />}
          {variant === 'C' && <VariantC {...props} />}
          {variant === 'D' && <VariantD {...props} />}
        </div>
      </div>
      <VariantSwitcher
        variants={VARIANTS.map(v => ({ key: v, name: VARIANT_NAMES[v] }))}
        current={variant}
        onChange={changeVariant}
      />
    </>
  )
}
