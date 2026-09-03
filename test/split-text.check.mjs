import assert from 'node:assert/strict'
import { splitText } from '../lib/index.js'
assert.deepEqual(splitText(''), [''])
assert.deepEqual(splitText('abc'), ['abc'])
const big = 'x'.repeat(5999) + '\u{1F600}' + 'y'.repeat(20)
const parts = splitText(big)
assert.equal(parts.length, 2)
assert.ok(parts[0].endsWith('\u{1F600}'))
assert.equal([...parts.join('')].length, [...big].length)
console.log('split-text OK')
