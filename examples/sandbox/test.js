// 零依賴的測試，讓 workflow 有真實的「跑測試」步驟可執行。
const assert = require('assert');
const { greet } = require('./src/greet');

assert.strictEqual(greet('World'), 'Hello, World!');
console.log('OK - all tests passed');
