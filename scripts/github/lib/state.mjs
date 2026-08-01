import { existsSync } from 'node:fs'
import { readTextLF, writeFileAtomic } from './util.mjs'

const STATE_PATH = 'planning/state.json'

export function loadState() {
  if (!existsSync(STATE_PATH)) {
    return {
      schemaVersion: 1,
      repo: null,
      project: null,
      labels: {},
      milestones: {},
      fields: {},
      statusConfigured: null,
      views: {},
      issues: {},
      lastStep: null,
      updatedAt: null,
    }
  }
  return JSON.parse(readTextLF(STATE_PATH))
}

// Every successful remote create/verify checkpoints here. Only server-returned
// values are stored; nothing in this file is ever hand-invented.
export function saveState(state, step) {
  if (step) state.lastStep = step
  state.updatedAt = new Date().toISOString()
  writeFileAtomic(STATE_PATH, JSON.stringify(state, null, 2) + '\n')
}
