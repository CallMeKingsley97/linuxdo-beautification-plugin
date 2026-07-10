// ==UserScript==
// @name         LINUX DO Beautification
// @namespace    https://linux.do/
// @version      0.2.1
// @description  LINUX DO 帖子楼中楼、书签与自定义高亮
// @author       linuxdo-beautification-plugin
// @match        https://linux.do/*
// @icon         https://linux.do/favicon.ico
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_registerMenuCommand
// @grant        unsafeWindow
// @run-at       document-idle
// ==/UserScript==

(function () {
  "use strict";

  const STYLE_ID = "ldo-beautification-style";
  const CONFIG_KEY = "ldo-beautification-config";
  const MAX_NEST_DEPTH = 3;
  const TOPIC_POST_SELECTOR = ".topic-post[data-post-number]";
  const TOPIC_ROW_SELECTOR =
    ".topic-list-item, tr[data-topic-id], .latest-topic-list-item, .category-topic-link";
  const FOLLOWED_AUTHOR_KEYS = [
    "followed",
    "following",
    "is_followed",
    "isFollowed",
    "is_following",
    "isFollowing",
    "user_following",
    "userFollowing",
    "current_user_following",
    "currentUserFollowing",
  ];
  const DEFAULT_CONFIG = {
    followedEnabled: true,
    followedColor: "#40b883",
    keywordsEnabled: true,
    keywordRules: [],
  };

  const state = {
    isMutating: false,
    isScheduled: false,
    config: loadConfig(),
    lastTopicKey: "",
    topicJsonKey: "",
    topicJsonRelations: new Map(),
    topicJsonLoading: null,
    postPlaceholders: new WeakMap(),
    ignoreMutationsUntil: 0,
  };

  function start() {
    injectStyle();
    registerMenuCommands();
    patchHistory();
    observePage();
    scheduleEnhance(0);
    window.addEventListener("load", () => scheduleEnhance(100));
    window.addEventListener("popstate", () => scheduleEnhance(120));
    document.addEventListener("click", () => scheduleEnhance(180), true);
  }

  function injectStyle() {
    if (document.getElementById(STYLE_ID)) {
      return;
    }

    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = `
      :root {
        --ldo-nested-line: #4e9f7a;
        --ldo-nested-bg: color-mix(in srgb, #4e9f7a 6%, var(--secondary, #fff));
        --ldo-nested-border: color-mix(in srgb, #4e9f7a 22%, var(--primary-low, #e7e7e7));
        --ldo-nested-muted: color-mix(in srgb, #4e9f7a 48%, var(--primary-medium, #888));
        --ldo-bookmark-bg: color-mix(in srgb, #f2b84b 18%, transparent);
        --ldo-bookmark-bg-strong: color-mix(in srgb, #f2b84b 28%, transparent);
        --ldo-bookmark-border: #d18818;
        --ldo-bookmark-title: color-mix(in srgb, #a95f00 86%, var(--primary, #222));
        --ldo-highlight-color: #40b883;
      }

      html.ldo-beautification-ready ${TOPIC_POST_SELECTOR}.ldo-has-nested-replies > article.boxed {
        box-shadow: inset 2px 0 0 color-mix(in srgb, var(--ldo-nested-line) 64%, transparent);
      }

      html.ldo-beautification-ready .ldo-nested-replies {
        position: relative;
        margin: 8px 0 8px 54px;
        padding: 2px 0 2px 20px;
        border-left: 1px solid var(--ldo-nested-border);
      }

      html.ldo-beautification-ready .ldo-nested-replies::before {
        content: "";
        position: absolute;
        top: 22px;
        left: -1px;
        width: 16px;
        height: 1px;
        background: var(--ldo-nested-border);
      }

      html.ldo-beautification-ready ${TOPIC_POST_SELECTOR}.ldo-nested-post {
        margin-top: 8px;
        margin-bottom: 8px;
      }

      html.ldo-beautification-ready ${TOPIC_POST_SELECTOR}.ldo-nested-post > article.boxed {
        border: 1px solid var(--ldo-nested-border);
        border-left: 2px solid var(--ldo-nested-line);
        border-radius: 6px;
        background: var(--ldo-nested-bg);
        box-shadow: none;
      }

      html.ldo-beautification-ready .ldo-reply-context {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        width: fit-content;
        max-width: 100%;
        margin: 0 10px 4px 0;
        padding: 1px 7px;
        border: 1px solid var(--ldo-nested-border);
        border-radius: 6px;
        color: var(--ldo-nested-muted);
        background: color-mix(in srgb, var(--ldo-nested-line) 7%, var(--secondary, #fff));
        font-size: 0.78rem;
        font-weight: 650;
        line-height: 1.35;
        text-decoration: none;
      }

      html.ldo-beautification-ready .ldo-reply-context:hover {
        color: var(--ldo-nested-line);
        background: color-mix(in srgb, var(--ldo-nested-line) 12%, var(--secondary, #fff));
        text-decoration: none;
      }

      html.ldo-beautification-ready ${TOPIC_POST_SELECTOR}.ldo-reply-orphan > article.boxed {
        border-left: 3px solid var(--ldo-nested-line);
      }

      html.ldo-beautification-ready .topic-list-item.ldo-bookmarked-topic,
      html.ldo-beautification-ready tr.ldo-bookmarked-topic,
      html.ldo-beautification-ready .latest-topic-list-item.ldo-bookmarked-topic,
      html.ldo-beautification-ready .category-topic-link.ldo-bookmarked-topic {
        position: relative;
        background: linear-gradient(90deg, var(--ldo-bookmark-bg-strong), transparent 72%) !important;
        box-shadow: inset 4px 0 0 var(--ldo-bookmark-border);
      }

      html.ldo-beautification-ready .ldo-bookmarked-topic a.title,
      html.ldo-beautification-ready .ldo-bookmarked-topic .title a,
      html.ldo-beautification-ready .ldo-bookmarked-topic .main-link a {
        color: var(--ldo-bookmark-title) !important;
        font-weight: 700;
      }

      html.ldo-beautification-ready ${TOPIC_POST_SELECTOR}.ldo-bookmarked-post > article.boxed {
        background: var(--ldo-bookmark-bg);
        box-shadow: inset 4px 0 0 var(--ldo-bookmark-border);
      }

      html.ldo-beautification-ready .ldo-bookmark-control,
      html.ldo-beautification-ready .ldo-bookmark-control .d-icon-bookmark,
      html.ldo-beautification-ready .ldo-bookmarked-topic .d-icon-bookmark,
      html.ldo-beautification-ready .ldo-bookmarked-post .d-icon-bookmark {
        color: var(--ldo-bookmark-border) !important;
        fill: var(--ldo-bookmark-border) !important;
      }

      html.ldo-beautification-ready body.ldo-current-topic-bookmarked .topic-title,
      html.ldo-beautification-ready body.ldo-current-topic-bookmarked .title-wrapper {
        background: linear-gradient(90deg, var(--ldo-bookmark-bg), transparent 72%);
        box-shadow: inset 4px 0 0 var(--ldo-bookmark-border);
      }

      html.ldo-beautification-ready .ldo-highlighted-topic {
        background:
          linear-gradient(
            90deg,
            color-mix(in srgb, var(--ldo-highlight-color) 18%, transparent),
            color-mix(in srgb, var(--ldo-highlight-color) 5%, transparent) 76%
          ) !important;
        box-shadow: inset 4px 0 0 var(--ldo-highlight-color);
      }

      html.ldo-beautification-ready .ldo-highlighted-topic a.title,
      html.ldo-beautification-ready .ldo-highlighted-topic .title a,
      html.ldo-beautification-ready .ldo-highlighted-topic .main-link a {
        font-weight: 720;
      }

      html.ldo-beautification-ready ${TOPIC_POST_SELECTOR}.ldo-highlighted-post > article.boxed {
        background:
          linear-gradient(
            90deg,
            color-mix(in srgb, var(--ldo-highlight-color) 15%, transparent),
            color-mix(in srgb, var(--ldo-highlight-color) 5%, transparent) 78%
          ) !important;
        border-color: color-mix(in srgb, var(--ldo-highlight-color) 35%, var(--primary-low, #e7e7e7));
        box-shadow: inset 4px 0 0 var(--ldo-highlight-color);
      }

      html.ldo-beautification-ready ${TOPIC_POST_SELECTOR}.ldo-highlighted-post.ldo-nested-post > article.boxed {
        border-left-color: var(--ldo-highlight-color);
      }

      html.ldo-beautification-ready .ldo-highlighted-followed .names a,
      html.ldo-beautification-ready .ldo-highlighted-followed .username a {
        color: var(--ldo-highlight-color) !important;
      }

      .ldo-settings-backdrop {
        position: fixed;
        inset: 0;
        z-index: 99999;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
        background: rgba(0, 0, 0, 0.42);
      }

      .ldo-settings-dialog {
        width: min(760px, calc(100vw - 32px));
        max-height: min(760px, calc(100vh - 32px));
        overflow: auto;
        border: 1px solid var(--primary-low, #ddd);
        border-radius: 8px;
        color: var(--primary, #222);
        background: var(--secondary, #fff);
        box-shadow: 0 18px 48px rgba(0, 0, 0, 0.28);
      }

      .ldo-settings-header,
      .ldo-settings-footer {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding: 16px 18px;
        border-bottom: 1px solid var(--primary-low, #ddd);
      }

      .ldo-settings-footer {
        justify-content: flex-end;
        border-top: 1px solid var(--primary-low, #ddd);
        border-bottom: 0;
      }

      .ldo-settings-title {
        margin: 0;
        font-size: 1.1rem;
        line-height: 1.35;
      }

      .ldo-settings-body {
        display: grid;
        gap: 18px;
        padding: 18px;
      }

      .ldo-settings-section {
        display: grid;
        gap: 10px;
      }

      .ldo-settings-section-title {
        margin: 0;
        font-size: 0.95rem;
        font-weight: 720;
      }

      .ldo-settings-row {
        display: flex;
        align-items: center;
        gap: 10px;
      }

      .ldo-settings-label {
        display: grid;
        gap: 6px;
        font-size: 0.86rem;
        color: var(--primary-medium, #666);
      }

      .ldo-settings-dialog input[type="text"],
      .ldo-settings-dialog textarea {
        width: 100%;
        box-sizing: border-box;
        border: 1px solid var(--primary-low, #ddd);
        border-radius: 6px;
        padding: 8px 10px;
        color: var(--primary, #222);
        background: var(--secondary, #fff);
        font: inherit;
      }

      .ldo-settings-dialog textarea {
        min-height: 92px;
        resize: vertical;
      }

      .ldo-keyword-list {
        display: grid;
        gap: 8px;
      }

      .ldo-keyword-row {
        display: grid;
        grid-template-columns: minmax(0, 1fr) 48px 38px 38px;
        align-items: center;
        gap: 8px;
      }

      .ldo-settings-dialog .ldo-keyword-input {
        min-width: 0;
      }

      .ldo-settings-dialog .ldo-keyword-color {
        width: 48px !important;
        height: 34px;
        min-width: 48px;
        box-sizing: border-box;
        border: 1px solid var(--primary-low-mid, #bbb);
        border-radius: 6px;
        padding: 2px;
        background: transparent;
      }

      .ldo-settings-dialog .ldo-keyword-enabled {
        justify-self: center;
        width: 18px !important;
        height: 18px;
        min-width: 18px;
        margin: 0;
      }

      .ldo-settings-dialog .ldo-keyword-remove {
        justify-self: center;
      }

      .ldo-settings-button {
        border: 1px solid var(--primary-low-mid, #bbb);
        border-radius: 6px;
        padding: 7px 12px;
        color: var(--primary, #222);
        background: var(--secondary, #fff);
        cursor: pointer;
        font: inherit;
      }

      .ldo-settings-button:hover {
        border-color: var(--primary-medium, #888);
      }

      .ldo-settings-button-primary {
        border-color: #2f8f68;
        color: #fff;
        background: #2f8f68;
      }

      .ldo-settings-icon-button {
        width: 34px;
        height: 34px;
        padding: 0;
      }

      .ldo-settings-hint {
        margin: 0;
        color: var(--primary-medium, #777);
        font-size: 0.78rem;
        line-height: 1.45;
      }

      @media (max-width: 760px) {
        html.ldo-beautification-ready .ldo-nested-replies {
          margin-left: 10px;
          padding-left: 12px;
        }

        html.ldo-beautification-ready ${TOPIC_POST_SELECTOR}.ldo-nested-post > article.boxed {
          border-radius: 6px;
        }

        html.ldo-beautification-ready .ldo-reply-context {
          white-space: normal;
        }

        .ldo-keyword-row {
          grid-template-columns: minmax(0, 1fr) 48px 38px 38px;
        }
      }
    `;
    document.head.appendChild(style);
    document.documentElement.classList.add("ldo-beautification-ready");
  }

  function registerMenuCommands() {
    if (typeof GM_registerMenuCommand === "function") {
      GM_registerMenuCommand("LINUX DO 美化设置", openSettingsPanel);
    }

    window.LDOBeautificationSettings = openSettingsPanel;
  }

  function loadConfig() {
    const saved = storageGet(CONFIG_KEY, {});
    return normalizeConfig(saved);
  }

  function saveConfig(config) {
    state.config = normalizeConfig(config);
    storageSet(CONFIG_KEY, state.config);
    scheduleEnhance(0);
  }

  function normalizeConfig(config) {
    const source = config && typeof config === "object" ? config : {};
    return {
      followedEnabled: source.followedEnabled !== false,
      followedColor: normalizeColor(source.followedColor, DEFAULT_CONFIG.followedColor),
      keywordsEnabled: source.keywordsEnabled !== false,
      keywordRules: normalizeKeywordRules(source.keywordRules),
    };
  }

  function storageGet(key, fallback) {
    try {
      if (typeof GM_getValue === "function") {
        return GM_getValue(key, fallback);
      }
      const raw = localStorage.getItem(key);
      return raw ? JSON.parse(raw) : fallback;
    } catch {
      return fallback;
    }
  }

  function storageSet(key, value) {
    try {
      if (typeof GM_setValue === "function") {
        GM_setValue(key, value);
        return;
      }
      localStorage.setItem(key, JSON.stringify(value));
    } catch {
    }
  }

  function openSettingsPanel() {
    document.querySelector(".ldo-settings-backdrop")?.remove();

    const draft = normalizeConfig(state.config);
    const backdrop = createElement("div", "ldo-settings-backdrop");
    const dialog = createElement("div", "ldo-settings-dialog");
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    let closeOnEscape;
    const closeDialog = () => {
      backdrop.remove();
      if (closeOnEscape) {
        document.removeEventListener("keydown", closeOnEscape);
      }
    };

    const header = createElement("div", "ldo-settings-header");
    const title = createElement("h2", "ldo-settings-title", "LINUX DO 美化设置");
    const closeButton = createElement("button", "ldo-settings-button ldo-settings-icon-button", "×");
    closeButton.type = "button";
    closeButton.setAttribute("aria-label", "关闭");
    closeButton.addEventListener("click", closeDialog);
    header.append(title, closeButton);

    const body = createElement("div", "ldo-settings-body");
    const followedSection = createFollowedSettingsSection(draft);
    const keywordSection = createKeywordSettingsSection(draft);
    body.append(followedSection.section, keywordSection.section);

    const footer = createElement("div", "ldo-settings-footer");
    const cancelButton = createElement("button", "ldo-settings-button", "取消");
    const saveButton = createElement("button", "ldo-settings-button ldo-settings-button-primary", "保存");
    cancelButton.type = "button";
    saveButton.type = "button";
    cancelButton.addEventListener("click", closeDialog);
    saveButton.addEventListener("click", () => {
      saveConfig({
        followedEnabled: followedSection.enabled.checked,
        followedColor: followedSection.color.value,
        keywordsEnabled: keywordSection.enabled.checked,
        keywordRules: keywordSection.getRules(),
      });
      closeDialog();
    });
    footer.append(cancelButton, saveButton);

    dialog.append(header, body, footer);
    backdrop.append(dialog);
    backdrop.addEventListener("click", (event) => {
      if (event.target === backdrop) {
        closeDialog();
      }
    });
    closeOnEscape = (event) => {
      if (event.key === "Escape") {
        closeDialog();
      }
    };
    document.addEventListener("keydown", closeOnEscape);
    document.body.appendChild(backdrop);
  }

  function createFollowedSettingsSection(config) {
    const section = createElement("section", "ldo-settings-section");
    const title = createElement("h3", "ldo-settings-section-title", "关注作者高亮");
    const enabledLabel = createElement("label", "ldo-settings-row");
    const enabled = document.createElement("input");
    enabled.type = "checkbox";
    enabled.checked = config.followedEnabled;
    enabledLabel.append(enabled, document.createTextNode("启用关注作者高亮"));

    const colorLabel = createElement("label", "ldo-settings-label", "高亮颜色");
    const color = document.createElement("input");
    color.type = "color";
    color.value = config.followedColor;
    colorLabel.appendChild(color);

    const hint = createElement(
      "p",
      "ldo-settings-hint",
      "脚本会读取站点暴露的关注状态，不需要手动填写用户名。"
    );

    section.append(title, enabledLabel, colorLabel, hint);
    return { section, enabled, color };
  }

  function createKeywordSettingsSection(config) {
    const section = createElement("section", "ldo-settings-section");
    const title = createElement("h3", "ldo-settings-section-title", "关键词高亮");
    const enabledLabel = createElement("label", "ldo-settings-row");
    const enabled = document.createElement("input");
    enabled.type = "checkbox";
    enabled.checked = config.keywordsEnabled;
    enabledLabel.append(enabled, document.createTextNode("启用关键词高亮"));

    const list = createElement("div", "ldo-keyword-list");
    const addButton = createElement("button", "ldo-settings-button", "添加关键词");
    addButton.type = "button";

    const renderRule = (rule = {}) => {
      const row = createElement("div", "ldo-keyword-row");
      const keyword = document.createElement("input");
      const color = document.createElement("input");
      const enabledRule = document.createElement("input");
      const remove = createElement("button", "ldo-settings-button ldo-settings-icon-button", "×");

      keyword.type = "text";
      keyword.className = "ldo-keyword-input";
      keyword.placeholder = "关键词";
      keyword.value = rule.keyword || "";
      color.type = "color";
      color.className = "ldo-keyword-color";
      color.value = normalizeColor(rule.color, "#ffd166");
      enabledRule.type = "checkbox";
      enabledRule.className = "ldo-keyword-enabled";
      enabledRule.checked = rule.enabled !== false;
      enabledRule.title = "启用此关键词";
      remove.type = "button";
      remove.classList.add("ldo-keyword-remove");
      remove.setAttribute("aria-label", "删除关键词");
      remove.addEventListener("click", () => row.remove());

      row.append(keyword, color, enabledRule, remove);
      list.appendChild(row);
    };

    config.keywordRules.forEach(renderRule);
    if (!config.keywordRules.length) {
      renderRule({ keyword: "", color: "#ffd166", enabled: true });
    }
    addButton.addEventListener("click", () => renderRule({ keyword: "", color: "#ffd166", enabled: true }));

    const hint = createElement("p", "ldo-settings-hint", "关键词会匹配主题标题和帖子内容，不区分大小写。");

    section.append(title, enabledLabel, list, addButton, hint);
    return {
      section,
      enabled,
      getRules() {
        return Array.from(list.querySelectorAll(".ldo-keyword-row"))
          .map((row) => {
            const [keyword, color, enabledRule] = row.querySelectorAll("input");
            return {
              keyword: keyword.value.trim(),
              color: color.value,
              enabled: enabledRule.checked,
            };
          })
          .filter((rule) => rule.keyword);
      },
    };
  }

  function createElement(tagName, className, textContent = "") {
    const element = document.createElement(tagName);
    if (className) {
      element.className = className;
    }
    if (textContent) {
      element.textContent = textContent;
    }
    return element;
  }

  function normalizeKeywordRules(value) {
    if (!Array.isArray(value)) {
      return [];
    }

    return value
      .map((rule) => ({
        keyword: String(rule?.keyword || "").trim(),
        color: normalizeColor(rule?.color, "#ffd166"),
        enabled: rule?.enabled !== false,
      }))
      .filter((rule) => rule.keyword);
  }

  function normalizeColor(value, fallback) {
    return /^#[\da-f]{6}$/i.test(String(value || "")) ? value : fallback;
  }

  function getPageWindow() {
    return typeof unsafeWindow !== "undefined" ? unsafeWindow : window;
  }

  function patchHistory() {
    const pageWindow = getPageWindow();
    if (pageWindow.__ldoBeautificationHistoryPatched) {
      return;
    }
    pageWindow.__ldoBeautificationHistoryPatched = true;

    ["pushState", "replaceState"].forEach((method) => {
      const original = pageWindow.history[method];
      pageWindow.history[method] = function patchedHistoryMethod(...args) {
        const result = original.apply(this, args);
        scheduleEnhance(120);
        return result;
      };
    });
  }

  function observePage() {
    const observer = new MutationObserver((mutations) => {
      if (state.isMutating || Date.now() < state.ignoreMutationsUntil) {
        return;
      }
      if (
        mutations.some(
          (mutation) =>
            mutation.type === "childList" ||
            (mutation.type === "attributes" &&
              ["aria-pressed", "title", "aria-label", "data-bookmarked"].includes(mutation.attributeName))
        )
      ) {
        scheduleEnhance(120);
      }
    });

    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["aria-pressed", "title", "aria-label", "data-bookmarked"],
    });
  }

  function scheduleEnhance(delay = 80) {
    if (state.isScheduled) {
      return;
    }

    state.isScheduled = true;
    window.setTimeout(() => {
      state.isScheduled = false;
      enhancePage();
    }, delay);
  }

  function enhancePage() {
    const topicInfo = getTopicInfo();
    const topicKey = topicInfo ? topicInfo.key : "";

    if (topicKey !== state.lastTopicKey) {
      restoreNestedPosts();
      state.lastTopicKey = topicKey;
      state.topicJsonKey = "";
      state.topicJsonRelations = new Map();
      state.topicJsonLoading = null;
    }

    enhanceBookmarks();

    if (!topicInfo) {
      restoreNestedPosts();
      enhanceHighlights();
      return;
    }

    loadTopicJsonRelations(topicInfo);
    enhanceReplyNesting(topicInfo);
    enhanceHighlights();
  }

  function getTopicInfo() {
    const parts = location.pathname.split("/").filter(Boolean);
    if (parts[0] !== "t") {
      return null;
    }

    if (parts.length >= 3 && isPostNumber(parts[2])) {
      return {
        key: parts[2],
        id: parts[2],
        slug: parts[1],
        basePath: `/t/${parts[1]}/${parts[2]}`,
      };
    }

    if (parts.length >= 2 && isPostNumber(parts[1])) {
      return {
        key: parts[1],
        id: parts[1],
        slug: "",
        basePath: `/t/${parts[1]}`,
      };
    }

    return null;
  }

  function isPostNumber(value) {
    return /^\d+$/.test(String(value || ""));
  }

  function loadTopicJsonRelations(topicInfo) {
    if (!topicInfo || state.topicJsonKey === topicInfo.key || state.topicJsonLoading) {
      return;
    }

    state.topicJsonLoading = fetch(`${topicInfo.basePath}.json`, {
      credentials: "include",
      headers: {
        Accept: "application/json",
      },
    })
      .then((response) => {
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }
        return response.json();
      })
      .then((topic) => {
        const relations = new Map();
        const posts = Array.isArray(topic?.post_stream?.posts) ? topic.post_stream.posts : [];
        posts.forEach((post) => {
          const number = toNumber(post.post_number);
          if (!number) {
            return;
          }
          relations.set(number, {
            id: post.id,
            number,
            parentNumber: toNumber(post.reply_to_post_number),
            username: post.username || "",
            bookmarked: Boolean(post.bookmarked),
            followed: readBooleanFromKeys(post, FOLLOWED_AUTHOR_KEYS),
          });
        });

        state.topicJsonKey = topicInfo.key;
        state.topicJsonRelations = relations;
      })
      .catch(() => {
        state.topicJsonKey = topicInfo.key;
        state.topicJsonRelations = new Map();
      })
      .finally(() => {
        state.topicJsonLoading = null;
        scheduleEnhance(80);
      });
  }

  function enhanceReplyNesting(topicInfo) {
    const posts = getRenderedPosts();
    if (!posts.length) {
      return;
    }

    const postElements = new Map();
    posts.forEach((post) => {
      const number = getPostNumber(post);
      if (number) {
        postElements.set(number, post);
      }
    });

    const relations = collectPostRelations();
    if (!relations.size) {
      return;
    }

    state.isMutating = true;
    try {
      posts.forEach((post) => {
        post.classList.remove("ldo-has-nested-replies");
      });

      postElements.forEach((post, number) => {
        const relation = relations.get(number);
        const parentNumber = relation?.parentNumber;
        const parentPost = parentNumber ? postElements.get(parentNumber) : null;

        post.classList.toggle("ldo-bookmarked-post", Boolean(relation?.bookmarked));

        if (!parentNumber || parentNumber === number) {
          restorePostIfNested(post);
          resetPostNestingState(post);
          return;
        }

        if (!parentPost || wouldCreateCycle(number, parentNumber, relations)) {
          restorePostIfNested(post);
          markOrphanReply(post, parentNumber, topicInfo);
          return;
        }

        movePostIntoParent(post, parentPost, parentNumber, getReplyDepth(number, relations), topicInfo);
      });

      cleanupReplyContainers();
    } finally {
      state.isMutating = false;
      state.ignoreMutationsUntil = Date.now() + 250;
    }
  }

  function getRenderedPosts() {
    return Array.from(document.querySelectorAll(TOPIC_POST_SELECTOR)).filter(
      (post) => !post.closest(".d-modal")
    );
  }

  function restorePostIfNested(post) {
    if (!post.classList.contains("ldo-nested-post")) {
      return;
    }

    const placeholder = state.postPlaceholders.get(post);
    if (placeholder?.parentNode) {
      placeholder.replaceWith(post);
    }
  }

  function restoreNestedPosts() {
    const nestedPosts = Array.from(document.querySelectorAll(`${TOPIC_POST_SELECTOR}.ldo-nested-post`));
    if (!nestedPosts.length) {
      cleanupReplyContainers();
      return;
    }

    state.isMutating = true;
    try {
      nestedPosts.forEach((post) => {
        const placeholder = state.postPlaceholders.get(post);
        if (placeholder?.parentNode) {
          placeholder.replaceWith(post);
        }
        resetPostNestingState(post);
      });
      cleanupReplyContainers();
    } finally {
      state.isMutating = false;
      state.ignoreMutationsUntil = Date.now() + 250;
    }
  }

  function resetPostNestingState(post) {
    post.classList.remove("ldo-nested-post", "ldo-reply-orphan");
    post.style.removeProperty("--ldo-depth");
    delete post.dataset.ldoReplyTo;
    clearReplyContext(post);
  }

  function cleanupReplyContainers() {
    document.querySelectorAll(".ldo-nested-replies").forEach((container) => {
      if (!container.querySelector(TOPIC_POST_SELECTOR)) {
        container.remove();
      }
    });

    document.querySelectorAll(`${TOPIC_POST_SELECTOR}.ldo-has-nested-replies`).forEach((post) => {
      if (!post.querySelector(":scope > .ldo-nested-replies")) {
        post.classList.remove("ldo-has-nested-replies");
      }
    });
  }

  function collectPostRelations() {
    const relations = new Map(state.topicJsonRelations);
    const discoursePosts = getDiscourseLoadedPosts();

    discoursePosts.forEach((post) => {
      const number = toNumber(readValue(post, ["post_number", "postNumber"]));
      if (!number) {
        return;
      }

      const existing = relations.get(number) || {};
      const rawParentNumber = readValue(post, ["reply_to_post_number", "replyToPostNumber"]);
      const rawBookmarked = readValue(post, ["bookmarked", "isBookmarked", "bookmark_id", "bookmarkId"]);
      const rawFollowed = readFirstValue(post, FOLLOWED_AUTHOR_KEYS);

      relations.set(number, {
        ...existing,
        id: readValue(post, ["id"]) ?? existing.id,
        number,
        parentNumber:
          rawParentNumber === undefined ? existing.parentNumber || null : toNumber(rawParentNumber),
        username: readValue(post, ["username"]) || existing.username || "",
        bookmarked: rawBookmarked === undefined ? Boolean(existing.bookmarked) : Boolean(rawBookmarked),
        followed: rawFollowed === undefined ? Boolean(existing.followed) : toBoolean(rawFollowed),
      });
    });

    return relations;
  }

  function getDiscourseLoadedPosts() {
    const controller = getDiscourseTopicController();
    const model = controller?.model;
    const postStream = model?.postStream || model?.post_stream || controller?.postStream;
    const posts =
      postStream?.posts ||
      postStream?.loadedPosts ||
      postStream?._posts ||
      postStream?.content ||
      [];

    if (Array.isArray(posts)) {
      return posts;
    }

    if (typeof posts.toArray === "function") {
      return posts.toArray();
    }

    return [];
  }

  function getDiscourseTopicController() {
    try {
      return getPageWindow().Discourse?.__container__?.lookup?.("controller:topic") || null;
    } catch {
      return null;
    }
  }

  function readFirstValue(object, keys) {
    for (const key of keys) {
      const value = readValue(object, [key]);
      if (value !== undefined) {
        return value;
      }
    }
    return undefined;
  }

  function readBooleanFromKeys(object, keys) {
    const value = readFirstValue(object, keys);
    return value === undefined ? false : toBoolean(value);
  }

  function toBoolean(value) {
    if (typeof value === "boolean") {
      return value;
    }
    if (typeof value === "number") {
      return value > 0;
    }
    if (typeof value === "string") {
      return ["1", "true", "yes", "y"].includes(value.trim().toLowerCase());
    }
    return Boolean(value);
  }

  function readValue(object, keys) {
    if (!object) {
      return undefined;
    }

    for (const key of keys) {
      if (Object.prototype.hasOwnProperty.call(object, key)) {
        return object[key];
      }
      if (typeof object.get === "function") {
        const value = object.get(key);
        if (value !== undefined) {
          return value;
        }
      }
    }

    return undefined;
  }

  function enhanceHighlights() {
    clearHighlights();

    const config = state.config;
    const keywordRules = config.keywordsEnabled
      ? config.keywordRules.filter((rule) => rule.enabled !== false && rule.keyword)
      : [];
    const relations = collectPostRelations();
    const topicRelations = collectTopicRelations();

    enhanceTopicRowHighlights(keywordRules, topicRelations);
    enhancePostHighlights(keywordRules, relations);
  }

  function clearHighlights() {
    document
      .querySelectorAll(".ldo-highlighted-topic, .ldo-highlighted-post, .ldo-highlighted-followed, .ldo-highlighted-keyword")
      .forEach((element) => {
        element.classList.remove(
          "ldo-highlighted-topic",
          "ldo-highlighted-post",
          "ldo-highlighted-followed",
          "ldo-highlighted-keyword"
        );
        element.style.removeProperty("--ldo-highlight-color");
        delete element.dataset.ldoHighlightReason;
        delete element.dataset.ldoHighlightKeyword;
      });
  }

  function enhanceTopicRowHighlights(keywordRules, topicRelations) {
    document.querySelectorAll(TOPIC_ROW_SELECTOR).forEach((row) => {
      const keywordMatch = findKeywordMatch(getTopicRowText(row), keywordRules);
      const followedMatch = state.config.followedEnabled && isTopicRowFollowed(row, topicRelations);

      if (keywordMatch) {
        applyHighlight(row, "topic", "keyword", keywordMatch.color, keywordMatch.keyword);
        return;
      }

      if (followedMatch) {
        applyHighlight(row, "topic", "followed", state.config.followedColor);
      }
    });
  }

  function enhancePostHighlights(keywordRules, relations) {
    getRenderedPosts().forEach((post) => {
      const relation = relations.get(getPostNumber(post));
      const keywordMatch = findKeywordMatch(getPostText(post), keywordRules);
      const followedMatch = state.config.followedEnabled && isPostFollowed(post, relation);

      if (keywordMatch) {
        applyHighlight(post, "post", "keyword", keywordMatch.color, keywordMatch.keyword);
        return;
      }

      if (followedMatch) {
        applyHighlight(post, "post", "followed", state.config.followedColor);
      }
    });
  }

  function applyHighlight(element, target, reason, color, keyword = "") {
    element.classList.add(target === "post" ? "ldo-highlighted-post" : "ldo-highlighted-topic");
    element.classList.add(reason === "followed" ? "ldo-highlighted-followed" : "ldo-highlighted-keyword");
    element.style.setProperty("--ldo-highlight-color", normalizeColor(color, state.config.followedColor));
    element.dataset.ldoHighlightReason = reason;
    if (keyword) {
      element.dataset.ldoHighlightKeyword = keyword;
    }
  }

  function findKeywordMatch(text, keywordRules) {
    if (!text || !keywordRules.length) {
      return null;
    }

    const haystack = text.toLowerCase();
    return keywordRules.find((rule) => haystack.includes(rule.keyword.toLowerCase())) || null;
  }

  function getTopicRowText(row) {
    const titleElements = row.querySelectorAll("a.title, .title a, .main-link a[href*='/t/'], a[href*='/t/']");
    const text = Array.from(titleElements)
      .map((element) => element.textContent.trim())
      .filter(Boolean)
      .join(" ");
    return text || row.textContent || "";
  }

  function isTopicRowFollowed(row, topicRelations) {
    if (readBooleanFromDom(row, FOLLOWED_AUTHOR_KEYS)) {
      return true;
    }

    const topicId = getTopicRowId(row);
    return topicId ? Boolean(topicRelations.get(topicId)?.followed) : false;
  }

  function getTopicRowId(row) {
    const idFromDataset = toNumber(row.dataset.topicId);
    if (idFromDataset) {
      return idFromDataset;
    }

    const topicLink = row.querySelector("a[href*='/t/']");
    const match = topicLink?.getAttribute("href")?.match(/\/t\/[^/]+\/(\d+)/);
    return match ? toNumber(match[1]) : null;
  }

  function isPostFollowed(post, relation) {
    return Boolean(relation?.followed) || readBooleanFromDom(post, FOLLOWED_AUTHOR_KEYS);
  }

  function getPostText(post) {
    const content = post.querySelector(".cooked") || post.querySelector(".post__body") || post;
    return content.textContent || "";
  }

  function collectTopicRelations() {
    const relations = new Map();
    getDiscourseLoadedTopics().forEach((topic) => {
      const id = toNumber(readValue(topic, ["id", "topic_id", "topicId"]));
      if (!id) {
        return;
      }
      relations.set(id, {
        followed: isTopicModelFollowed(topic),
      });
    });
    return relations;
  }

  function getDiscourseLoadedTopics() {
    const pageWindow = getPageWindow();
    const container = pageWindow.Discourse?.__container__;
    if (!container?.lookup) {
      return [];
    }

    const controllers = [
      "controller:discovery/topics",
      "controller:discovery",
      "controller:latest",
      "controller:category",
      "controller:tag",
      "controller:topic-list",
    ];

    return controllers.flatMap((name) => getTopicsFromController(safeContainerLookup(container, name))).filter(Boolean);
  }

  function safeContainerLookup(container, name) {
    try {
      return container.lookup(name);
    } catch {
      return null;
    }
  }

  function getTopicsFromController(controller) {
    const candidates = [
      controller?.model,
      controller?.topicList,
      controller?.model?.topicList,
      controller?.model?.topic_list,
    ];

    return candidates.flatMap((candidate) => toArray(candidate?.topics || candidate?.topic_list?.topics || candidate));
  }

  function toArray(value) {
    if (Array.isArray(value)) {
      return value;
    }
    if (typeof value?.toArray === "function") {
      return value.toArray();
    }
    return [];
  }

  function isTopicModelFollowed(topic) {
    if (readBooleanFromKeys(topic, FOLLOWED_AUTHOR_KEYS)) {
      return true;
    }

    const posters = toArray(readValue(topic, ["posters", "participants"]));
    return posters.some((poster) => readBooleanFromKeys(poster, FOLLOWED_AUTHOR_KEYS));
  }

  function readBooleanFromDom(root, keys) {
    return [root, ...root.querySelectorAll("[data-followed], [data-following], [data-user-following], [data-current-user-following], .followed, .following")]
      .some((element) => {
        if (element.classList?.contains("followed") || element.classList?.contains("following")) {
          return true;
        }

        return keys.some((key) => {
          const dataValue = element.dataset?.[toDatasetKey(key)];
          if (dataValue !== undefined) {
            return toBoolean(dataValue);
          }
          const attrValue = element.getAttribute?.(toDataAttribute(key));
          return attrValue !== null && toBoolean(attrValue);
        });
      });
  }

  function toDatasetKey(key) {
    return String(key).replace(/[-_]+([a-z])/g, (_, letter) => letter.toUpperCase());
  }

  function toDataAttribute(key) {
    return `data-${String(key).replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`).replace(/_/g, "-")}`;
  }

  function movePostIntoParent(post, parentPost, parentNumber, depth, topicInfo) {
    const container = ensureReplyContainer(parentPost);

    if (post.parentElement !== container) {
      let placeholder = state.postPlaceholders.get(post);
      if ((!placeholder || !placeholder.parentNode) && !post.classList.contains("ldo-nested-post")) {
        placeholder = document.createComment(`ldo-beautification-post-${getPostNumber(post)}`);
        post.parentNode.insertBefore(placeholder, post);
        state.postPlaceholders.set(post, placeholder);
      }

      container.appendChild(post);
    }

    post.classList.add("ldo-nested-post");
    post.classList.remove("ldo-reply-orphan");
    post.style.setProperty("--ldo-depth", String(Math.min(depth, MAX_NEST_DEPTH)));
    post.dataset.ldoReplyTo = String(parentNumber);
    parentPost.classList.add("ldo-has-nested-replies");
    ensureReplyContext(post, parentNumber, topicInfo);
  }

  function ensureReplyContainer(parentPost) {
    const existing = Array.from(parentPost.children).find((child) =>
      child.classList?.contains("ldo-nested-replies")
    );
    if (existing) {
      return existing;
    }

    const container = document.createElement("div");
    container.className = "ldo-nested-replies";
    parentPost.appendChild(container);
    return container;
  }

  function ensureReplyContext(post, parentNumber, topicInfo) {
    const body = post.querySelector(".topic-meta-data") || post.querySelector(".post__body") || post;
    let context = post.querySelector(":scope .ldo-reply-context");
    if (!context) {
      context = document.createElement("a");
      context.className = "ldo-reply-context";
      body.insertBefore(context, body.firstChild);
    }

    context.href = `${topicInfo.basePath}/${parentNumber}`;
    context.textContent = `回复 #${parentNumber}`;
    context.title = `跳转到 #${parentNumber}`;
  }

  function clearReplyContext(post) {
    post.querySelectorAll(":scope .ldo-reply-context").forEach((context) => context.remove());
  }

  function markOrphanReply(post, parentNumber, topicInfo) {
    post.classList.add("ldo-reply-orphan");
    post.classList.remove("ldo-nested-post");
    post.style.removeProperty("--ldo-depth");
    post.dataset.ldoReplyTo = String(parentNumber);
    ensureReplyContext(post, parentNumber, topicInfo);
  }

  function getReplyDepth(number, relations) {
    let depth = 0;
    let current = number;
    const seen = new Set();

    while (depth < MAX_NEST_DEPTH) {
      const parentNumber = relations.get(current)?.parentNumber;
      if (!parentNumber || seen.has(parentNumber)) {
        break;
      }
      seen.add(parentNumber);
      depth += 1;
      current = parentNumber;
    }

    return Math.max(depth, 1);
  }

  function wouldCreateCycle(number, parentNumber, relations) {
    let current = parentNumber;
    const seen = new Set([number]);

    while (current) {
      if (seen.has(current)) {
        return true;
      }
      seen.add(current);
      current = relations.get(current)?.parentNumber;
    }

    return false;
  }

  function getPostNumber(post) {
    return toNumber(post?.dataset?.postNumber);
  }

  function toNumber(value) {
    const number = Number(value);
    return Number.isInteger(number) && number > 0 ? number : null;
  }

  function enhanceBookmarks() {
    document
      .querySelectorAll(".ldo-bookmarked-topic, .ldo-bookmarked-post, .ldo-bookmark-control")
      .forEach((element) => {
        element.classList.remove("ldo-bookmarked-topic", "ldo-bookmarked-post", "ldo-bookmark-control");
      });

    document.body.classList.toggle("ldo-current-topic-bookmarked", isCurrentTopicBookmarked());

    const bookmarkMarkers = document.querySelectorAll(getBookmarkMarkerSelector());
    bookmarkMarkers.forEach((marker) => {
      marker.classList.add("ldo-bookmark-control");

      const topicRow = marker.closest(
        ".topic-list-item, tr[data-topic-id], .latest-topic-list-item, .category-topic-link"
      );
      if (topicRow) {
        topicRow.classList.add("ldo-bookmarked-topic");
      }

      const post = marker.closest(TOPIC_POST_SELECTOR);
      if (post && isActiveBookmarkMarker(marker)) {
        post.classList.add("ldo-bookmarked-post");
      }
    });

    markBookmarkedPostsFromModels();
  }

  function getBookmarkMarkerSelector() {
    return [
      ".topic-status .d-icon-bookmark",
      ".topic-status[title*='书签']",
      ".topic-status[aria-label*='书签']",
      ".topic-status[title*='bookmark' i]",
      ".topic-status[aria-label*='bookmark' i]",
      ".bookmark.bookmarked",
      ".bookmark[aria-pressed='true']",
      ".bookmark[title*='移除']",
      ".bookmark[aria-label*='移除']",
      ".bookmark[title*='remove' i]",
      ".bookmark[aria-label*='remove' i]",
      "[data-bookmarked='true']",
    ].join(",");
  }

  function isActiveBookmarkMarker(marker) {
    return Boolean(
      marker.matches(".topic-status .d-icon-bookmark, .bookmark.bookmarked, .bookmark[aria-pressed='true'], [data-bookmarked='true']") ||
        marker.closest(".bookmark.bookmarked, .bookmark[aria-pressed='true'], [data-bookmarked='true']")
    );
  }

  function isCurrentTopicBookmarked() {
    const controller = getDiscourseTopicController();
    const topic = controller?.model;
    return Boolean(readValue(topic, ["bookmarked", "isBookmarked", "bookmark_id", "bookmarkId"]));
  }

  function markBookmarkedPostsFromModels() {
    collectPostRelations().forEach((relation, number) => {
      if (!relation.bookmarked) {
        return;
      }
      const post = document.querySelector(`${TOPIC_POST_SELECTOR}[data-post-number="${number}"]`);
      post?.classList.add("ldo-bookmarked-post");
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
