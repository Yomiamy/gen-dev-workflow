// 沙盒用的最小模組，故意留有明顯的擴充點供冒煙測試修改。
function greet(name) {
  return `Hello, ${name}!`;
}

module.exports = { greet };
