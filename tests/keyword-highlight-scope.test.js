"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");
const scriptPath = path.join(projectRoot, "linuxdo-beautification.user.js");
const readmePath = path.join(projectRoot, "README.md");
const source = fs.readFileSync(scriptPath, "utf8");
const readme = fs.readFileSync(readmePath, "utf8");

function getFunctionSource(name) {
  const start = source.indexOf(`  function ${name}(`);
  assert.notEqual(start, -1, `未找到函数：${name}`);

  const end = source.indexOf("\n  function ", start + 1);
  return source.slice(start, end === -1 ? source.length : end);
}

const topicHighlightSource = getFunctionSource("enhanceTopicRowHighlights");
const postHighlightSource = getFunctionSource("enhancePostHighlights");
const titleTextSource = getFunctionSource("getTopicRowTitleText");

assert.match(
  topicHighlightSource,
  /findKeywordMatch\(getTopicRowTitleText\(row\), keywordRules\)/,
  "主题关键词必须只使用标题文本进行匹配"
);
assert.doesNotMatch(postHighlightSource, /findKeywordMatch/, "帖子内容不应参与关键词匹配");
assert.doesNotMatch(source, /function getPostText\(/, "不应保留帖子正文关键词读取逻辑");
assert.doesNotMatch(titleTextSource, /row\.textContent/, "标题缺失时不应回退匹配整行内容");
assert.match(source, /关键词仅匹配主题标题，不区分大小写。/, "设置说明应与实际行为一致");
assert.match(readme, /仅在命中主题标题时高亮显示/, "README 应说明关键词仅匹配主题标题");

console.log("关键词高亮范围测试通过");
