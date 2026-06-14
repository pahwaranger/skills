// ReviewWindowController.swift — removed in Slice 8.
//
// The Review window is now opened via SwiftUI's `openWindow(id: "review")`
// environment action, injected into `SkillRowView` inside the `MenuBarExtra`
// content. The focused-skill handoff uses `AppModel.reviewFocusSkill` (an
// `@Observable` property) instead of `UserDefaults`. No AppKit hacks required.
