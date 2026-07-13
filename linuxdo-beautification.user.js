// ==UserScript==
// @name         LINUX DO Beautification
// @namespace    https://linux.do/
// @version      0.3.0
// @description  LINUX DO Apple 风格界面、书签高亮、关注作者、代码块复制、长图折叠、引用折叠、状态徽章、悬浮快捷操作
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
  const FOLLOWED_USERS_CACHE_KEY = "ldo-beautification-followed-users-v1";
  const FOLLOW_SYNC_LOCK_KEY = "ldo-beautification-follow-sync-lock";
  const FOLLOW_SYNC_LOCK_TTL_MS = 60_000;
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
  const DEFAULT_FEATURES = {
    codeCopy: true,
    longImage: true,
    quoteCollapse: true,
    topicBadges: true,
    visitedFade: true,
    floatingActions: true,
  };
  const FEATURE_META = [
    { key: "codeCopy", name: "代码块复制按钮", desc: "帖子内代码块右上角显示 Apple 风格复制按钮。" },
    { key: "longImage", name: "长图自动折叠", desc: "超过 520px 高度的图片默认折叠，点击展开。" },
    { key: "quoteCollapse", name: "引用折叠", desc: "较长的嵌套引用默认收起，点击标题栏展开。" },
    { key: "topicBadges", name: "主题状态徽章", desc: "已解决/置顶/精华/抽奖用彩色胶囊突出显示。" },
    { key: "visitedFade", name: "已读主题淡化", desc: "已读过的主题标题淡化，突出未读内容。" },
    { key: "floatingActions", name: "悬浮快捷操作", desc: "右下角显示返回顶部/底部按钮，向下滚动后出现。" },
  ];
  const LONG_IMAGE_MIN_HEIGHT = 520;
  const QUOTE_COLLAPSE_MIN_HEIGHT = 220;
  const DEFAULT_CONFIG = {
    followedEnabled: true,
    followedColor: "#40b883",
    keywordsEnabled: true,
    keywordRules: [],
    features: { ...DEFAULT_FEATURES },
  };

  const state = {
    isScheduled: false,
    config: loadConfig(),
    followedUsers: new Set(),
    followedUsersOwner: "",
    followSyncPromise: null,
    followMutations: new Map(),
    floatingActionsRoot: null,
  };

  function start() {
    injectStyle();
    registerMenuCommands();
    patchHistory();
    initFloatingActions();
    observePage();
    scheduleEnhance(0);
    window.addEventListener("load", () => scheduleEnhance(100));
    window.addEventListener("popstate", () => scheduleEnhance(120));
    window.addEventListener("scroll", updateFloatingActionsVisibility, { passive: true });
    document.addEventListener("click", handleFollowButtonClick, true);
  }

  function injectStyle() {
    document.documentElement.classList.add("ldo-apple-ui");
    if (document.getElementById(STYLE_ID)) {
      document.documentElement.classList.add("ldo-beautification-ready");
      return;
    }

    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = `
      :root {
        --ldo-apple-font:
          -apple-system,
          BlinkMacSystemFont,
          "SF Pro Text",
          "SF Pro Display",
          "PingFang SC",
          "Microsoft YaHei",
          sans-serif;
        --ldo-apple-page-bg: color-mix(in srgb, var(--secondary, #fff) 94%, #000 6%);
        --ldo-apple-surface: color-mix(in srgb, var(--secondary, #fff) 84%, transparent);
        --ldo-apple-surface-solid: var(--secondary, #fff);
        --ldo-apple-surface-elevated:
          color-mix(in srgb, var(--secondary, #fff) 94%, var(--primary, #222) 6%);
        --ldo-apple-label: var(--primary, #1d1d1f);
        --ldo-apple-label-secondary: var(--primary-medium, #6e6e73);
        --ldo-apple-label-tertiary: color-mix(in srgb, var(--primary, #222) 52%, transparent);
        --ldo-apple-separator: color-mix(in srgb, var(--primary, #222) 14%, transparent);
        --ldo-apple-separator-strong: color-mix(in srgb, var(--primary, #222) 24%, transparent);
        --ldo-apple-hover: color-mix(in srgb, var(--primary, #222) 6%, transparent);
        --ldo-apple-selected: color-mix(in srgb, #34c759 14%, transparent);
        --ldo-apple-accent: #34c759;
        --ldo-apple-focus: var(--tertiary, #007aff);
        --ldo-apple-radius-small: 8px;
        --ldo-apple-radius-medium: 12px;
        --ldo-apple-radius-large: 18px;
        --ldo-apple-shadow: 0 10px 32px rgba(0, 0, 0, 0.1);
        --ldo-apple-shadow-elevated: 0 18px 48px rgba(0, 0, 0, 0.2);
        --ldo-apple-transition: 180ms cubic-bezier(0.25, 0.1, 0.25, 1);
        --ldo-bookmark-bg: color-mix(in srgb, #f2b84b 18%, transparent);
        --ldo-bookmark-bg-strong: color-mix(in srgb, #f2b84b 28%, transparent);
        --ldo-bookmark-border: #d18818;
        --ldo-bookmark-title: color-mix(in srgb, #a95f00 86%, var(--primary, #222));
        --ldo-highlight-color: #40b883;
      }

      /* 第一阶段：全局视觉系统 */
      html.ldo-apple-ui body {
        color: var(--ldo-apple-label);
        background: var(--ldo-apple-page-bg);
        font-family: var(--ldo-apple-font);
        -webkit-font-smoothing: antialiased;
        -moz-osx-font-smoothing: grayscale;
        text-rendering: optimizeLegibility;
      }

      html.ldo-apple-ui button,
      html.ldo-apple-ui input,
      html.ldo-apple-ui select,
      html.ldo-apple-ui textarea {
        font-family: var(--ldo-apple-font);
      }

      html.ldo-apple-ui ::selection {
        color: var(--ldo-apple-label);
        background: color-mix(in srgb, var(--ldo-apple-focus) 24%, transparent);
      }

      html.ldo-apple-ui :focus-visible {
        outline: 3px solid color-mix(in srgb, var(--ldo-apple-focus) 42%, transparent);
        outline-offset: 2px;
      }

      html.ldo-apple-ui #main-outlet {
        padding-top: 20px;
      }

      html.ldo-apple-ui a,
      html.ldo-apple-ui button,
      html.ldo-apple-ui .btn {
        transition:
          color var(--ldo-apple-transition),
          background-color var(--ldo-apple-transition),
          border-color var(--ldo-apple-transition),
          opacity var(--ldo-apple-transition),
          transform var(--ldo-apple-transition),
          box-shadow var(--ldo-apple-transition);
      }

      html.ldo-apple-ui {
        scrollbar-color: var(--ldo-apple-separator-strong) transparent;
        scrollbar-width: thin;
      }

      html.ldo-apple-ui ::-webkit-scrollbar {
        width: 10px;
        height: 10px;
      }

      html.ldo-apple-ui ::-webkit-scrollbar-thumb {
        border: 3px solid transparent;
        border-radius: 999px;
        background: var(--ldo-apple-separator-strong);
        background-clip: padding-box;
      }

      html.ldo-apple-ui ::-webkit-scrollbar-track {
        background: transparent;
      }

      /* 第二阶段：顶部导航 */
      html.ldo-apple-ui .d-header-wrap {
        background: transparent;
      }

      html.ldo-apple-ui .d-header {
        min-height: 54px;
        border-bottom: 1px solid var(--ldo-apple-separator);
        background: var(--ldo-apple-surface);
        box-shadow: none;
        backdrop-filter: saturate(165%) blur(20px);
        -webkit-backdrop-filter: saturate(165%) blur(20px);
      }

      html.ldo-apple-ui .d-header .wrap {
        min-height: 54px;
      }

      html.ldo-apple-ui .d-header-icons .icon,
      html.ldo-apple-ui .d-header .header-buttons .btn,
      html.ldo-apple-ui .d-header .panel .widget-button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-width: 36px;
        min-height: 36px;
        border: 0;
        border-radius: 10px;
        color: var(--ldo-apple-label-secondary);
        background: transparent;
      }

      html.ldo-apple-ui .d-header-icons .icon:hover,
      html.ldo-apple-ui .d-header-icons .icon:focus-visible,
      html.ldo-apple-ui .d-header .header-buttons .btn:hover,
      html.ldo-apple-ui .d-header .panel .widget-button:hover {
        color: var(--ldo-apple-label);
        background: var(--ldo-apple-hover);
      }

      html.ldo-apple-ui .d-header .title img,
      html.ldo-apple-ui .d-header .title .logo-big,
      html.ldo-apple-ui .d-header .title .logo-small {
        filter: saturate(0.92) contrast(1.02);
      }

      /* 第二阶段：左侧导航 */
      html.ldo-apple-ui .sidebar-wrapper {
        border-right: 1px solid var(--ldo-apple-separator);
        background: var(--ldo-apple-surface);
        box-shadow: none;
        backdrop-filter: saturate(145%) blur(18px);
        -webkit-backdrop-filter: saturate(145%) blur(18px);
      }

      html.ldo-apple-ui .sidebar-container {
        padding-top: 10px;
      }

      html.ldo-apple-ui .sidebar-section-wrapper {
        padding-inline: 8px;
      }

      html.ldo-apple-ui .sidebar-section-header {
        min-height: 30px;
        padding-inline: 10px;
        color: var(--ldo-apple-label-tertiary);
        font-size: 0.72rem;
        font-weight: 650;
        letter-spacing: 0.01em;
      }

      html.ldo-apple-ui .sidebar-section-link-wrapper {
        margin-block: 2px;
      }

      html.ldo-apple-ui .sidebar-section-link {
        min-height: 38px;
        border-radius: 10px;
        padding-inline: 10px;
        color: var(--ldo-apple-label-secondary);
      }

      html.ldo-apple-ui .sidebar-section-link:hover {
        color: var(--ldo-apple-label);
        background: var(--ldo-apple-hover);
      }

      html.ldo-apple-ui .sidebar-section-link.active,
      html.ldo-apple-ui .sidebar-section-link.--active {
        color: var(--ldo-apple-label);
        background: var(--ldo-apple-selected);
        font-weight: 650;
      }

      html.ldo-apple-ui .sidebar-section-link-prefix,
      html.ldo-apple-ui .sidebar-section-link-suffix {
        opacity: 0.76;
      }

      /* 第二阶段：主题列表 */
      html.ldo-apple-ui .topic-list,
      html.ldo-apple-ui .latest-topic-list {
        overflow: hidden;
        border: 1px solid var(--ldo-apple-separator);
        border-radius: var(--ldo-apple-radius-large);
        background: var(--ldo-apple-surface-solid);
        box-shadow: var(--ldo-apple-shadow);
      }

      html.ldo-apple-ui table.topic-list {
        border-collapse: separate;
        border-spacing: 0;
      }

      html.ldo-apple-ui .topic-list thead,
      html.ldo-apple-ui .topic-list-header {
        color: var(--ldo-apple-label-tertiary);
        background: var(--ldo-apple-surface-elevated);
        font-size: 0.72rem;
        font-weight: 650;
      }

      html.ldo-apple-ui .topic-list th {
        border-bottom: 1px solid var(--ldo-apple-separator);
        padding-block: 9px;
      }

      html.ldo-apple-ui .topic-list-item,
      html.ldo-apple-ui .latest-topic-list-item {
        background: transparent;
      }

      html.ldo-apple-ui .topic-list-item td,
      html.ldo-apple-ui .latest-topic-list-item {
        border-bottom: 1px solid var(--ldo-apple-separator);
        padding-top: 13px;
        padding-bottom: 13px;
        transition: background-color var(--ldo-apple-transition);
      }

      html.ldo-apple-ui .topic-list-item:last-child td,
      html.ldo-apple-ui .latest-topic-list-item:last-child {
        border-bottom: 0;
      }

      html.ldo-apple-ui .topic-list-item:hover td,
      html.ldo-apple-ui .latest-topic-list-item:hover {
        background: var(--ldo-apple-hover);
      }

      html.ldo-apple-ui .topic-list-item.selected td,
      html.ldo-apple-ui .topic-list-item.visited:hover td {
        background: color-mix(in srgb, var(--ldo-apple-focus) 7%, transparent);
      }

      html.ldo-apple-ui .topic-list .main-link a.title,
      html.ldo-apple-ui .topic-list .topic-title,
      html.ldo-apple-ui .latest-topic-list-item .main-link a {
        color: var(--ldo-apple-label);
        font-size: 1rem;
        font-weight: 620;
        line-height: 1.38;
        letter-spacing: -0.008em;
      }

      html.ldo-apple-ui .topic-list .topic-excerpt,
      html.ldo-apple-ui .latest-topic-list-item .topic-excerpt {
        margin-top: 4px;
        color: var(--ldo-apple-label-secondary);
        line-height: 1.5;
      }

      html.ldo-apple-ui .topic-list .num,
      html.ldo-apple-ui .topic-list .activity,
      html.ldo-apple-ui .topic-list .age,
      html.ldo-apple-ui .latest-topic-list-item .topic-stats {
        color: var(--ldo-apple-label-secondary);
        font-variant-numeric: tabular-nums;
        font-weight: 540;
      }

      html.ldo-apple-ui .topic-list .posters img.avatar,
      html.ldo-apple-ui .latest-topic-list-item img.avatar {
        border-radius: 50%;
        box-shadow: 0 0 0 1px var(--ldo-apple-separator);
        transition:
          transform var(--ldo-apple-transition),
          box-shadow var(--ldo-apple-transition);
      }

      html.ldo-apple-ui .topic-list .posters a:hover img.avatar,
      html.ldo-apple-ui .latest-topic-list-item a:hover img.avatar {
        z-index: 2;
        box-shadow: 0 0 0 2px color-mix(in srgb, var(--ldo-apple-focus) 34%, transparent);
        transform: scale(1.05);
      }

      html.ldo-apple-ui .badge-category__wrapper,
      html.ldo-apple-ui .discourse-tag.box,
      html.ldo-apple-ui .discourse-tag.simple {
        border-radius: 6px;
      }

      html.ldo-apple-ui .discourse-tag.box {
        border: 0;
        color: var(--ldo-apple-label-secondary);
        background: var(--ldo-apple-hover);
        font-size: 0.72rem;
        font-weight: 560;
      }

      /* 第二阶段：主题与帖子阅读流 */
      html.ldo-apple-ui #topic-title {
        margin-bottom: 12px;
        padding-bottom: 14px;
        border-bottom: 1px solid var(--ldo-apple-separator);
      }

      html.ldo-apple-ui #topic-title h1,
      html.ldo-apple-ui #topic-title .fancy-title {
        color: var(--ldo-apple-label);
        font-size: clamp(1.38rem, 2vw, 1.82rem);
        font-weight: 680;
        line-height: 1.26;
        letter-spacing: -0.018em;
      }

      html.ldo-apple-ui ${TOPIC_POST_SELECTOR} > article.boxed {
        border-bottom: 1px solid var(--ldo-apple-separator);
        border-radius: var(--ldo-apple-radius-medium);
        background: transparent;
        box-shadow: none;
        transition:
          background-color var(--ldo-apple-transition),
          box-shadow var(--ldo-apple-transition);
      }

      html.ldo-apple-ui ${TOPIC_POST_SELECTOR}:hover > article.boxed,
      html.ldo-apple-ui ${TOPIC_POST_SELECTOR}:focus-within > article.boxed {
        background: color-mix(in srgb, var(--ldo-apple-surface-solid) 78%, transparent);
      }

      html.ldo-apple-ui .topic-avatar {
        padding-top: 20px;
      }

      html.ldo-apple-ui .topic-avatar img.avatar,
      html.ldo-apple-ui .topic-meta-data img.avatar {
        border-radius: 50%;
        box-shadow: 0 0 0 1px var(--ldo-apple-separator);
      }

      html.ldo-apple-ui .topic-body {
        padding-top: 18px;
        padding-bottom: 22px;
      }

      html.ldo-apple-ui .topic-meta-data {
        min-height: 34px;
      }

      html.ldo-apple-ui .topic-meta-data .names,
      html.ldo-apple-ui .topic-meta-data .names a,
      html.ldo-apple-ui .topic-meta-data .username a {
        color: var(--ldo-apple-label);
        font-weight: 650;
      }

      html.ldo-apple-ui .topic-meta-data .post-info,
      html.ldo-apple-ui .topic-meta-data .relative-date {
        color: var(--ldo-apple-label-tertiary);
      }

      html.ldo-apple-ui .cooked {
        color: var(--ldo-apple-label);
        font-size: 1rem;
        line-height: 1.74;
        letter-spacing: 0.002em;
      }

      html.ldo-apple-ui .cooked p,
      html.ldo-apple-ui .cooked ul,
      html.ldo-apple-ui .cooked ol {
        margin-bottom: 1em;
      }

      html.ldo-apple-ui .cooked blockquote {
        margin-inline: 0;
        border-left: 3px solid var(--ldo-apple-separator-strong);
        border-radius: 0 var(--ldo-apple-radius-small) var(--ldo-apple-radius-small) 0;
        padding: 10px 14px;
        color: var(--ldo-apple-label-secondary);
        background: var(--ldo-apple-surface-elevated);
      }

      html.ldo-apple-ui .cooked pre,
      html.ldo-apple-ui .cooked .md-table {
        overflow: auto;
        border: 1px solid var(--ldo-apple-separator);
        border-radius: var(--ldo-apple-radius-medium);
        background: var(--ldo-apple-surface-elevated);
        box-shadow: none;
      }

      html.ldo-apple-ui .post-menu-area,
      html.ldo-apple-ui .post-controls {
        opacity: 0.72;
        transition: opacity var(--ldo-apple-transition);
      }

      html.ldo-apple-ui ${TOPIC_POST_SELECTOR}:hover .post-menu-area,
      html.ldo-apple-ui ${TOPIC_POST_SELECTOR}:focus-within .post-menu-area,
      html.ldo-apple-ui ${TOPIC_POST_SELECTOR}:hover .post-controls,
      html.ldo-apple-ui ${TOPIC_POST_SELECTOR}:focus-within .post-controls {
        opacity: 1;
      }

      html.ldo-apple-ui .post-controls .actions button,
      html.ldo-apple-ui .post-menu-area button {
        min-width: 34px;
        min-height: 34px;
        border-radius: var(--ldo-apple-radius-small);
      }

      html.ldo-apple-ui .post-controls .actions button:hover,
      html.ldo-apple-ui .post-menu-area button:hover {
        background: var(--ldo-apple-hover);
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

      html.ldo-beautification-ready .ldo-highlighted-followed .names a,
      html.ldo-beautification-ready .ldo-highlighted-followed .username a {
        color: var(--ldo-highlight-color) !important;
      }

      html.ldo-beautification-ready .ldo-followed-badge {
        display: inline-flex;
        align-items: center;
        width: fit-content;
        margin-left: 5px;
        border: 1px solid color-mix(in srgb, var(--ldo-highlight-color) 42%, transparent);
        border-radius: 999px;
        padding: 0 5px;
        color: color-mix(in srgb, var(--ldo-highlight-color) 82%, var(--primary, #222));
        background: color-mix(in srgb, var(--ldo-highlight-color) 12%, transparent);
        font-size: 0.65rem;
        font-weight: 700;
        line-height: 1.45;
        white-space: nowrap;
        vertical-align: middle;
      }

      html.ldo-beautification-ready .posters .ldo-followed-badge,
      html.ldo-beautification-ready .topic-list-posters .ldo-followed-badge,
      html.ldo-beautification-ready .topic-users .ldo-followed-badge {
        display: none;
      }

      html.ldo-beautification-ready .ldo-follow-notification {
        --ldo-follow-notification-color: var(--ldo-highlight-color);
        box-shadow: inset 2px 0 0 var(--ldo-follow-notification-color);
      }

      html.ldo-beautification-ready .ldo-follow-notification-topic {
        --ldo-follow-notification-color: #40b883;
      }

      html.ldo-beautification-ready .ldo-follow-notification-reply {
        --ldo-follow-notification-color: #5b8def;
      }

      html.ldo-beautification-ready .ldo-follow-notification-follower {
        --ldo-follow-notification-color: #d28b3c;
      }

      html.ldo-beautification-ready .ldo-follow-notification-label {
        display: inline;
        margin-left: 4px;
        color: var(--ldo-follow-notification-color);
        font-size: 0.6rem;
        font-weight: 600;
        opacity: 0.8;
        white-space: nowrap;
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

      /* 代码块复制按钮 */
      html.ldo-apple-ui .cooked pre {
        position: relative;
      }

      html.ldo-apple-ui .ldo-code-copy-btn {
        position: absolute;
        top: 8px;
        right: 8px;
        z-index: 2;
        padding: 4px 10px;
        border: 1px solid var(--ldo-apple-separator);
        border-radius: 999px;
        color: var(--ldo-apple-label-secondary);
        background: color-mix(in srgb, var(--ldo-apple-surface-solid) 82%, transparent);
        backdrop-filter: saturate(160%) blur(10px);
        -webkit-backdrop-filter: saturate(160%) blur(10px);
        font-family: var(--ldo-apple-font);
        font-size: 0.72rem;
        font-weight: 620;
        letter-spacing: 0.02em;
        cursor: pointer;
        opacity: 0;
        transition: opacity var(--ldo-apple-transition), color var(--ldo-apple-transition),
          border-color var(--ldo-apple-transition), background-color var(--ldo-apple-transition);
      }

      html.ldo-apple-ui .cooked pre:hover .ldo-code-copy-btn,
      html.ldo-apple-ui .cooked pre:focus-within .ldo-code-copy-btn,
      html.ldo-apple-ui .ldo-code-copy-btn:focus-visible {
        opacity: 1;
      }

      html.ldo-apple-ui .ldo-code-copy-btn:hover {
        color: var(--ldo-apple-label);
        background: var(--ldo-apple-surface-solid);
      }
      html.ldo-apple-ui .ldo-code-copy-btn.ldo-copied {
        color: #0f7a3a;
        border-color: color-mix(in srgb, var(--ldo-apple-accent) 42%, transparent);
        background: color-mix(in srgb, var(--ldo-apple-accent) 18%, var(--ldo-apple-surface-solid));
      }

      /* 长图折叠 */
      html.ldo-apple-ui .cooked .ldo-long-image {
        position: relative;
        display: block;
        overflow: hidden;
        max-height: ${LONG_IMAGE_MIN_HEIGHT}px;
        margin: 12px 0;
        border-radius: var(--ldo-apple-radius-medium);
        cursor: zoom-in;
        transition: max-height var(--ldo-apple-transition);
      }

      html.ldo-apple-ui .cooked .ldo-long-image.ldo-expanded {
        max-height: none;
        cursor: zoom-out;
      }

      html.ldo-apple-ui .cooked .ldo-long-image > img {
        display: block;
        width: 100%;
        height: auto;
        margin: 0;
      }

      html.ldo-apple-ui .cooked .ldo-long-image::after {
        content: attr(data-ldo-hint);
        position: absolute;
        inset: auto 0 0 0;
        padding: 28px 12px 10px;
        color: #fff;
        font-size: 0.78rem;
        font-weight: 620;
        letter-spacing: 0.02em;
        text-align: center;
        background: linear-gradient(transparent, rgba(0, 0, 0, 0.62));
        pointer-events: none;
        transition: opacity var(--ldo-apple-transition);
      }

      html.ldo-apple-ui .cooked .ldo-long-image.ldo-expanded::after {
        opacity: 0;
      }

      html.ldo-apple-ui .cooked .ldo-long-image.ldo-expanded:hover::after {
        opacity: 1;
      }
      /* 引用折叠 */
      html.ldo-apple-ui .cooked aside.quote.ldo-quote-collapsible {
        position: relative;
        margin: 12px 0;
        border: 1px solid var(--ldo-apple-separator);
        border-radius: var(--ldo-apple-radius-small);
        background: var(--ldo-apple-surface-elevated);
        overflow: hidden;
      }

      html.ldo-apple-ui .cooked aside.quote.ldo-quote-collapsible > .title {
        display: flex;
        align-items: center;
        gap: 6px;
        padding: 6px 10px;
        color: var(--ldo-apple-label-secondary);
        background: color-mix(in srgb, var(--ldo-apple-surface-elevated) 60%, transparent);
        cursor: pointer;
        user-select: none;
      }

      html.ldo-apple-ui .cooked aside.quote.ldo-quote-collapsible > .title::after {
        content: "▾";
        margin-left: auto;
        color: var(--ldo-apple-label-tertiary);
        font-size: 0.7em;
        transition: transform var(--ldo-apple-transition);
      }

      html.ldo-apple-ui .cooked aside.quote.ldo-quote-collapsible.ldo-quote-collapsed > .title::after {
        transform: rotate(-90deg);
      }

      html.ldo-apple-ui .cooked aside.quote.ldo-quote-collapsible.ldo-quote-collapsed > blockquote {
        display: none;
      }

      html.ldo-apple-ui .cooked aside.quote.ldo-quote-collapsible > blockquote {
        margin: 0;
        border: 0;
        border-radius: 0;
        padding: 10px 14px;
        background: transparent;
      }
      /* 主题状态徽章 */
      html.ldo-apple-ui .ldo-topic-badges {
        display: inline-flex;
        flex-wrap: wrap;
        gap: 4px;
        margin-left: 6px;
        vertical-align: middle;
      }

      html.ldo-apple-ui .ldo-topic-badge {
        display: inline-flex;
        align-items: center;
        gap: 3px;
        padding: 1px 8px;
        border-radius: 999px;
        font-size: 0.68rem;
        font-weight: 640;
        line-height: 1.5;
        letter-spacing: 0.02em;
        white-space: nowrap;
      }

      html.ldo-apple-ui .ldo-topic-badge-solved {
        color: #0f7a3a;
        background: color-mix(in srgb, #34c759 22%, transparent);
      }

      html.ldo-apple-ui .ldo-topic-badge-pinned {
        color: #b45309;
        background: color-mix(in srgb, #f59e0b 22%, transparent);
      }

      html.ldo-apple-ui .ldo-topic-badge-featured {
        color: #7c3aed;
        background: color-mix(in srgb, #a78bfa 24%, transparent);
      }

      html.ldo-apple-ui .ldo-topic-badge-giveaway {
        color: #be185d;
        background: color-mix(in srgb, #ec4899 22%, transparent);
      }

      html.ldo-apple-ui .ldo-topic-badge-hot {
        color: #b91c1c;
        background: color-mix(in srgb, #ef4444 20%, transparent);
      }

      html.ldo-apple-ui .ldo-topic-badge-closed {
        color: var(--ldo-apple-label-secondary);
        background: var(--ldo-apple-hover);
      }

      /* 已读主题淡化 */
      html.ldo-apple-ui.ldo-fade-visited .topic-list-item.visited:not(.ldo-highlighted-topic):not(.ldo-bookmarked-topic) .main-link,
      html.ldo-apple-ui.ldo-fade-visited .latest-topic-list-item.visited:not(.ldo-highlighted-topic):not(.ldo-bookmarked-topic) .main-link {
        opacity: 0.52;
        transition: opacity var(--ldo-apple-transition);
      }

      html.ldo-apple-ui.ldo-fade-visited .topic-list-item.visited:hover .main-link,
      html.ldo-apple-ui.ldo-fade-visited .latest-topic-list-item.visited:hover .main-link {
        opacity: 1;
      }
      /* 悬浮快捷操作 */
      .ldo-floating-actions {
        position: fixed;
        right: 20px;
        bottom: 24px;
        z-index: 9998;
        display: flex;
        flex-direction: column;
        gap: 8px;
        opacity: 0;
        transform: translateY(12px);
        transition: opacity 220ms cubic-bezier(0.25, 0.1, 0.25, 1),
          transform 220ms cubic-bezier(0.25, 0.1, 0.25, 1);
        pointer-events: none;
      }

      .ldo-floating-actions.ldo-visible {
        opacity: 1;
        transform: translateY(0);
        pointer-events: auto;
      }

      .ldo-floating-btn {
        width: 42px;
        height: 42px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        padding: 0;
        border: 1px solid color-mix(in srgb, currentColor 12%, transparent);
        border-radius: 50%;
        color: var(--ldo-apple-label, #1d1d1f);
        background: color-mix(in srgb, var(--ldo-apple-surface-solid, #fff) 82%, transparent);
        backdrop-filter: saturate(160%) blur(16px);
        -webkit-backdrop-filter: saturate(160%) blur(16px);
        box-shadow: 0 6px 20px rgba(0, 0, 0, 0.14);
        cursor: pointer;
        transition: transform 160ms cubic-bezier(0.25, 0.1, 0.25, 1),
          background-color 160ms cubic-bezier(0.25, 0.1, 0.25, 1),
          box-shadow 160ms cubic-bezier(0.25, 0.1, 0.25, 1);
      }

      .ldo-floating-btn:hover {
        transform: translateY(-1px);
        background: var(--ldo-apple-surface-solid, #fff);
        box-shadow: 0 10px 24px rgba(0, 0, 0, 0.18);
      }

      .ldo-floating-btn:active {
        transform: translateY(0);
      }

      .ldo-floating-btn svg {
        width: 18px;
        height: 18px;
        fill: currentColor;
      }
      /* 设置面板 - 功能开关 */
      .ldo-feature-list {
        display: grid;
        gap: 4px;
      }

      .ldo-feature-row {
        display: grid;
        grid-template-columns: 20px 1fr;
        align-items: flex-start;
        gap: 10px;
        padding: 8px 10px;
        border-radius: 8px;
        transition: background-color 160ms ease;
      }

      .ldo-feature-row:hover {
        background: var(--primary-very-low, rgba(0, 0, 0, 0.04));
      }

      .ldo-feature-row input {
        margin-top: 3px;
      }

      .ldo-feature-name {
        font-weight: 620;
        color: var(--primary, #222);
      }

      .ldo-feature-desc {
        display: block;
        margin-top: 2px;
        color: var(--primary-medium, #777);
        font-size: 0.78rem;
        line-height: 1.5;
      }

      @media (max-width: 760px) {
        .ldo-floating-actions {
          right: 12px;
          bottom: 16px;
        }
        .ldo-floating-btn {
          width: 40px;
          height: 40px;
        }
      }

      @media (max-width: 760px) {
        html.ldo-apple-ui #main-outlet {
          padding-top: 12px;
        }

        html.ldo-apple-ui .d-header,
        html.ldo-apple-ui .d-header .wrap {
          min-height: 50px;
        }

        html.ldo-apple-ui .topic-list,
        html.ldo-apple-ui .latest-topic-list {
          border-inline: 0;
          border-radius: 0;
          box-shadow: none;
        }

        html.ldo-apple-ui .topic-list-item td,
        html.ldo-apple-ui .latest-topic-list-item {
          padding-top: 11px;
          padding-bottom: 11px;
        }

        html.ldo-apple-ui #topic-title {
          margin-inline: 4px;
          padding-bottom: 10px;
        }

        html.ldo-apple-ui #topic-title h1,
        html.ldo-apple-ui #topic-title .fancy-title {
          font-size: 1.3rem;
        }

        html.ldo-apple-ui ${TOPIC_POST_SELECTOR} > article.boxed {
          border-radius: 0;
        }

        html.ldo-apple-ui ${TOPIC_POST_SELECTOR}:hover > article.boxed,
        html.ldo-apple-ui ${TOPIC_POST_SELECTOR}:focus-within > article.boxed {
          background: transparent;
        }

        html.ldo-apple-ui .topic-body {
          padding-top: 14px;
          padding-bottom: 18px;
        }

        html.ldo-apple-ui .cooked {
          font-size: 0.98rem;
          line-height: 1.7;
        }

        html.ldo-apple-ui .post-menu-area,
        html.ldo-apple-ui .post-controls {
          opacity: 1;
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
      features: normalizeFeatures(source.features),
    };
  }

  function normalizeFeatures(value) {
    const source = value && typeof value === "object" ? value : {};
    const result = {};
    Object.keys(DEFAULT_FEATURES).forEach((key) => {
      result[key] = source[key] !== false;
    });
    return result;
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

  function ensureFollowedUsersForCurrentUser() {
    const owner = getCurrentUsername();
    if (!owner) {
      return;
    }

    hydrateFollowedUsersFromCache(owner);

    const dateKey = getLocalDateKey();
    const record = getFollowedUsersRecord(owner);
    if (record.lastAttemptDate === dateKey || state.followSyncPromise) {
      return;
    }

    state.followSyncPromise = runFollowedUsersDailySync(owner, dateKey).finally(() => {
      state.followSyncPromise = null;
    });
  }

  async function runFollowedUsersDailySync(owner, dateKey) {
    const lockName = `ldo-follow-sync:${owner}:${dateKey}`;
    if (navigator.locks?.request) {
      await navigator.locks.request(lockName, { ifAvailable: true }, async (lock) => {
        if (!lock) {
          scheduleFollowedUsersCacheRefresh(owner);
          return;
        }
        await performFollowedUsersDailySync(owner, dateKey);
      });
      return;
    }

    const lockToken = acquireFollowSyncLock(owner, dateKey);
    if (!lockToken) {
      scheduleFollowedUsersCacheRefresh(owner);
      return;
    }

    try {
      await performFollowedUsersDailySync(owner, dateKey);
    } finally {
      releaseFollowSyncLock(lockToken);
    }
  }

  async function performFollowedUsersDailySync(owner, dateKey) {
    const currentRecord = getFollowedUsersRecord(owner);
    if (currentRecord.lastAttemptDate === dateKey) {
      if (state.followedUsersOwner === owner) {
        hydrateFollowedUsersFromCache(owner);
      }
      return;
    }

    saveFollowedUsersRecord(owner, {
      ...currentRecord,
      lastAttemptDate: dateKey,
    });

    try {
      const response = await fetch(`/u/${encodeURIComponent(owner)}/follow/following.json`, {
        credentials: "include",
        headers: {
          Accept: "application/json",
          "X-Requested-With": "XMLHttpRequest",
        },
      });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }

      const payload = await response.json();
      const followedUsers = new Set(extractFollowedUsernames(payload));
      if (state.followedUsersOwner === owner) {
        state.followMutations.forEach((followed, username) => {
          if (followed) {
            followedUsers.add(username);
          } else {
            followedUsers.delete(username);
          }
        });
      }

      saveFollowedUsersRecord(owner, {
        users: Array.from(followedUsers).sort(),
        lastAttemptDate: dateKey,
        lastSuccessDate: dateKey,
        updatedAt: new Date().toISOString(),
      });
      if (state.followedUsersOwner === owner) {
        state.followMutations.clear();
        hydrateFollowedUsersFromCache(owner);
        scheduleEnhance(0);
      }
    } catch {
      if (state.followedUsersOwner === owner) {
        hydrateFollowedUsersFromCache(owner);
      }
    }
  }

  function extractFollowedUsernames(payload) {
    const users = Array.isArray(payload)
      ? payload
      : payload?.users || payload?.following || payload?.user_list?.users || [];
    if (!Array.isArray(users)) {
      return [];
    }

    return normalizeFollowedUsers(
      users.map((user) => readValue(user, ["username", "user_name", "userName"]))
    );
  }

  function hydrateFollowedUsersFromCache(owner) {
    const normalizedOwner = normalizeUsername(owner);
    if (!normalizedOwner) {
      return;
    }

    if (state.followedUsersOwner !== normalizedOwner) {
      state.followMutations.clear();
    }
    state.followedUsersOwner = normalizedOwner;
    state.followedUsers = new Set(getFollowedUsersRecord(normalizedOwner).users);
  }

  function loadFollowedUsersCache() {
    const cache = storageGet(FOLLOWED_USERS_CACHE_KEY, {});
    return {
      version: 1,
      accounts: cache?.accounts && typeof cache.accounts === "object" ? cache.accounts : {},
    };
  }

  function getFollowedUsersRecord(owner) {
    const cache = loadFollowedUsersCache();
    const record = cache.accounts[getFollowedUsersAccountKey(owner)] || {};
    return {
      users: normalizeFollowedUsers(record.users),
      lastAttemptDate: String(record.lastAttemptDate || ""),
      lastSuccessDate: String(record.lastSuccessDate || ""),
      updatedAt: String(record.updatedAt || ""),
    };
  }

  function saveFollowedUsersRecord(owner, record) {
    const normalizedOwner = normalizeUsername(owner);
    if (!normalizedOwner) {
      return;
    }

    const cache = loadFollowedUsersCache();
    cache.accounts[getFollowedUsersAccountKey(normalizedOwner)] = {
      users: normalizeFollowedUsers(record.users),
      lastAttemptDate: String(record.lastAttemptDate || ""),
      lastSuccessDate: String(record.lastSuccessDate || ""),
      updatedAt: String(record.updatedAt || ""),
    };
    storageSet(FOLLOWED_USERS_CACHE_KEY, cache);
  }

  function getFollowedUsersAccountKey(owner) {
    return `user:${normalizeUsername(owner)}`;
  }

  function getLocalDateKey() {
    const now = new Date();
    return [
      now.getFullYear(),
      String(now.getMonth() + 1).padStart(2, "0"),
      String(now.getDate()).padStart(2, "0"),
    ].join("-");
  }

  function scheduleFollowedUsersCacheRefresh(owner) {
    window.setTimeout(() => {
      if (getCurrentUsername() === owner) {
        hydrateFollowedUsersFromCache(owner);
        scheduleEnhance(0);
      }
    }, 1_500);
  }

  function acquireFollowSyncLock(owner, dateKey) {
    const now = Date.now();
    const token = `${owner}:${dateKey}:${now}:${Math.random().toString(36).slice(2)}`;
    try {
      const activeLock = JSON.parse(localStorage.getItem(FOLLOW_SYNC_LOCK_KEY) || "null");
      if (activeLock?.expiresAt > now) {
        return "";
      }

      localStorage.setItem(
        FOLLOW_SYNC_LOCK_KEY,
        JSON.stringify({ token, expiresAt: now + FOLLOW_SYNC_LOCK_TTL_MS })
      );
      const confirmedLock = JSON.parse(localStorage.getItem(FOLLOW_SYNC_LOCK_KEY) || "null");
      return confirmedLock?.token === token ? token : "";
    } catch {
      return token;
    }
  }

  function releaseFollowSyncLock(token) {
    try {
      const activeLock = JSON.parse(localStorage.getItem(FOLLOW_SYNC_LOCK_KEY) || "null");
      if (activeLock?.token === token) {
        localStorage.removeItem(FOLLOW_SYNC_LOCK_KEY);
      }
    } catch {
    }
  }

  function getCurrentUsername() {
    const pageWindow = getPageWindow();
    const candidates = [];
    try {
      candidates.push(pageWindow.Discourse?.User?.current?.());
    } catch {
    }

    const container = pageWindow.Discourse?.__container__;
    if (container?.lookup) {
      ["service:current-user", "controller:application"].forEach((name) => {
        try {
          const value = container.lookup(name);
          candidates.push(value, value?.currentUser, value?.model);
        } catch {
        }
      });
    }

    for (const candidate of candidates) {
      const username = getModelUsername(candidate);
      if (username) {
        return username;
      }
    }

    const currentUserElement = document.querySelector(
      ".d-header .current-user [data-user-card], .d-header .header-dropdown-toggle.current-user [data-user-card], #current-user [data-user-card]"
    );
    return getDomUsername(currentUserElement);
  }

  function handleFollowButtonClick(event) {
    const button = event.target?.closest?.("button");
    if (!button) {
      return;
    }

    const userContainer = button.closest(
      ".user-card, .user-card-container, .user-main, .user-content"
    );
    if (!userContainer) {
      return;
    }

    const model = getFollowTargetModel();
    const rawFollowed = readFirstValue(model, FOLLOWED_AUTHOR_KEYS);
    const buttonAction = detectFollowButtonAction(button);
    if (rawFollowed === undefined && !buttonAction) {
      return;
    }

    const username = getFollowTargetUsername(button, model);
    if (!username) {
      return;
    }

    const shouldFollow =
      rawFollowed === undefined ? buttonAction === "follow" : !toBoolean(rawFollowed);
    window.setTimeout(() => {
      confirmFollowStateChange({
        username,
        shouldFollow,
        model,
        container: userContainer,
        attempt: 1,
      });
    }, 900);
  }

  function confirmFollowStateChange({ username, shouldFollow, model, container, attempt }) {
    const latestModel = getFollowTargetModel(username) || model;
    const rawFollowed = readFirstValue(latestModel, FOLLOWED_AUTHOR_KEYS);
    if (rawFollowed !== undefined) {
      if (toBoolean(rawFollowed) === shouldFollow) {
        updateCachedFollowedUser(username, shouldFollow);
      } else {
        retryFollowStateConfirmation({ username, shouldFollow, model, container, attempt });
      }
      return;
    }

    const currentButton = Array.from(container?.querySelectorAll("button") || []).find((button) =>
      detectFollowButtonAction(button)
    );
    const currentAction = detectFollowButtonAction(currentButton);
    const domFollowed = currentAction === "unfollow";
    if (currentAction && domFollowed === shouldFollow) {
      updateCachedFollowedUser(username, shouldFollow);
      return;
    }
    retryFollowStateConfirmation({ username, shouldFollow, model, container, attempt });
  }

  function retryFollowStateConfirmation(context) {
    if (context.attempt >= 3) {
      return;
    }

    window.setTimeout(() => {
      confirmFollowStateChange({ ...context, attempt: context.attempt + 1 });
    }, 700 * context.attempt);
  }

  function detectFollowButtonAction(button) {
    if (!button) {
      return "";
    }

    const descriptor = [
      button.textContent,
      button.getAttribute("aria-label"),
      button.getAttribute("title"),
      button.className,
      button.querySelector("svg")?.getAttribute("class"),
      button.querySelector(".d-icon")?.getAttribute("class"),
    ]
      .filter(Boolean)
      .join(" ");

    if (/user-xmark|user-times|unfollow|取消关注|停止关注/i.test(descriptor)) {
      return "unfollow";
    }
    if (/user-plus|\bfollow\b|关注/i.test(descriptor)) {
      return "follow";
    }
    return "";
  }

  function getFollowTargetModel(expectedUsername = "") {
    const pageWindow = getPageWindow();
    const container = pageWindow.Discourse?.__container__;
    if (!container?.lookup) {
      return null;
    }

    const normalizedExpected = normalizeUsername(expectedUsername);
    for (const name of ["controller:user-card", "controller:user"]) {
      try {
        const controller = container.lookup(name);
        for (const model of [controller?.model, controller?.user]) {
          const username = getModelUsername(model);
          if (username && (!normalizedExpected || username === normalizedExpected)) {
            return model;
          }
        }
      } catch {
      }
    }
    return null;
  }

  function getFollowTargetUsername(button, model) {
    const modelUsername = getModelUsername(model);
    if (modelUsername) {
      return modelUsername;
    }

    const container = button.closest(".user-card, .user-card-container, .user-main, .user-content");
    const usernameElement = container?.querySelector(
      "[data-user-card], [data-username], a[href*='/u/']"
    );
    const domUsername = getDomUsername(usernameElement);
    if (domUsername) {
      return domUsername;
    }

    const match = location.pathname.match(/^\/u\/([^/]+)/i);
    return match ? normalizeUsername(decodeURIComponent(match[1])) : "";
  }

  function updateCachedFollowedUser(username, followed) {
    const owner = getCurrentUsername();
    const normalizedUsername = normalizeUsername(username);
    if (!owner || !normalizedUsername || normalizedUsername === owner) {
      return;
    }

    if (state.followedUsersOwner !== owner) {
      hydrateFollowedUsersFromCache(owner);
    }

    const record = getFollowedUsersRecord(owner);
    const followedUsers = new Set(record.users);
    if (followed) {
      followedUsers.add(normalizedUsername);
    } else {
      followedUsers.delete(normalizedUsername);
    }

    state.followMutations.set(normalizedUsername, followed);
    state.followedUsers = followedUsers;
    saveFollowedUsersRecord(owner, {
      ...record,
      users: Array.from(followedUsers).sort(),
      updatedAt: new Date().toISOString(),
    });
    scheduleEnhance(0);
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
    const featureSection = createFeatureSettingsSection(draft);
    const followedSection = createFollowedSettingsSection(draft);
    const keywordSection = createKeywordSettingsSection(draft);
    body.append(featureSection.section, followedSection.section, keywordSection.section);

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
        features: featureSection.getFeatures(),
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

  function createFeatureSettingsSection(config) {
    const section = createElement("section", "ldo-settings-section");
    const title = createElement("h3", "ldo-settings-section-title", "功能开关");
    const list = createElement("div", "ldo-feature-list");
    const inputs = {};

    FEATURE_META.forEach(({ key, name, desc }) => {
      const row = createElement("label", "ldo-feature-row");
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.checked = config.features[key] !== false;
      const textWrap = document.createElement("span");
      const nameEl = createElement("span", "ldo-feature-name", name);
      const descEl = createElement("span", "ldo-feature-desc", desc);
      textWrap.append(nameEl, descEl);
      row.append(checkbox, textWrap);
      list.appendChild(row);
      inputs[key] = checkbox;
    });

    section.append(title, list);
    return {
      section,
      getFeatures() {
        const result = {};
        Object.keys(inputs).forEach((key) => {
          result[key] = inputs[key].checked;
        });
        return result;
      },
    };
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
      "每天首次进入网站时同步一次关注用户，之后只读取本地名单；新关注或取消关注会自动增量更新。"
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

  function normalizeFollowedUsers(value) {
    const items = Array.isArray(value) ? value : String(value || "").split(/[\n,]+/);
    return Array.from(
      new Set(
        items
          .map(normalizeUsername)
          .filter(Boolean)
      )
    );
  }

  function normalizeUsername(value) {
    return String(value || "").trim().replace(/^@/, "").toLowerCase();
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
    applyFeatureFlags();
    ensureFollowedUsersForCurrentUser();
    enhanceBookmarks();
    enhanceHighlights();
    enhanceCodeBlocks();
    enhanceLongImages();
    enhanceQuotes();
    enhanceTopicBadges();
    updateFloatingActionsVisibility();
  }

  function applyFeatureFlags() {
    document.documentElement.classList.toggle(
      "ldo-fade-visited",
      Boolean(state.config.features.visitedFade)
    );
  }

  function getRenderedPosts() {
    return Array.from(document.querySelectorAll(TOPIC_POST_SELECTOR)).filter(
      (post) => !post.closest(".d-modal")
    );
  }

  function collectPostRelations() {
    const relations = new Map();
    const discoursePosts = getDiscourseLoadedPosts();

    discoursePosts.forEach((post) => {
      const number = toNumber(readValue(post, ["post_number", "postNumber"]));
      if (!number) {
        return;
      }

      const existing = relations.get(number) || {};
      const rawBookmarked = readValue(post, ["bookmarked", "isBookmarked", "bookmark_id", "bookmarkId"]);
      const rawFollowed = readFirstValue(post, FOLLOWED_AUTHOR_KEYS);

      relations.set(number, {
        ...existing,
        id: readValue(post, ["id"]) ?? existing.id,
        number,
        username: readValue(post, ["username"]) || existing.username || "",
        bookmarked: rawBookmarked === undefined ? Boolean(existing.bookmarked) : Boolean(rawBookmarked),
        followed: rawFollowed === undefined ? Boolean(existing.followed) : toBoolean(rawFollowed),
      });
    });

    mergeDomPostRelations(relations);

    return relations;
  }

  function mergeDomPostRelations(relations) {
    getRenderedPosts().forEach((post) => {
      const number = getPostNumber(post);
      if (!number) {
        return;
      }

      if (!relations.has(number)) {
        relations.set(number, { number });
      }
    });
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
    const followedUsers = new Set(state.followedUsers);
    const relations = collectPostRelations();
    const topicRelations = collectTopicRelations();

    enhanceTopicRowHighlights(keywordRules, topicRelations, followedUsers);
    enhancePostHighlights(keywordRules, relations, followedUsers);
    enhanceFollowNotifications();
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

  function enhanceTopicRowHighlights(keywordRules, topicRelations, followedUsers) {
    document.querySelectorAll(TOPIC_ROW_SELECTOR).forEach((row) => {
      const keywordMatch = findKeywordMatch(getTopicRowText(row), keywordRules);
      const followedMatch = isTopicRowFollowed(row, topicRelations, followedUsers);
      updateFollowedAuthorBadges(row, getTopicRowAuthorElements(row), followedMatch);

      if (keywordMatch) {
        applyHighlight(row, "topic", "keyword", keywordMatch.color, keywordMatch.keyword);
        return;
      }

      if (state.config.followedEnabled && followedMatch) {
        applyHighlight(row, "topic", "followed", state.config.followedColor);
      }
    });

  }

  function enhancePostHighlights(keywordRules, relations, followedUsers) {
    getRenderedPosts().forEach((post) => {
      const relation = relations.get(getPostNumber(post));
      const keywordMatch = findKeywordMatch(getPostText(post), keywordRules);
      const followedMatch = isPostFollowed(post, relation, followedUsers);
      const article = post.querySelector(":scope > article");
      updateFollowedAuthorBadges(
        article,
        [getPostAuthorElement(post)].filter(Boolean),
        followedMatch
      );

      if (keywordMatch) {
        applyHighlight(post, "post", "keyword", keywordMatch.color, keywordMatch.keyword);
        return;
      }

      if (state.config.followedEnabled && followedMatch) {
        applyHighlight(post, "post", "followed", state.config.followedColor);
      }
    });
  }

  function updateFollowedAuthorBadges(container, authorElements, followed) {
    if (!container) {
      return;
    }

    const targets = Array.from(new Set(authorElements.filter(Boolean)));
    const badges = Array.from(container.querySelectorAll(".ldo-followed-badge"));
    badges.forEach((badge) => {
      if (!followed || !targets.includes(badge.previousElementSibling)) {
        badge.remove();
      }
    });

    if (!followed) {
      return;
    }

    targets.forEach((target) => {
      if (target.nextElementSibling?.classList?.contains("ldo-followed-badge")) {
        return;
      }

      const badge = createElement("span", "ldo-followed-badge", "已关注");
      const username = getDomUsername(target);
      badge.title = username ? `已关注 @${username}` : "已关注该作者";
      target.parentNode?.insertBefore(badge, target.nextSibling);
    });
  }

  function enhanceFollowNotifications() {
    const definitions = [
      {
        code: "801",
        icon: "discourse-follow-new-topic",
        className: "ldo-follow-notification-topic",
        label: "关注用户新主题",
      },
      {
        code: "802",
        icon: "discourse-follow-new-reply",
        className: "ldo-follow-notification-reply",
        label: "关注用户新回复",
      },
      {
        code: "800",
        icon: "discourse-follow-new-follower",
        className: "ldo-follow-notification-follower",
        label: "新增关注者",
      },
    ];
    const matchedItems = new Map();

    definitions.forEach((definition) => {
      const selectors = [
        `[data-notification-type="${definition.code}"]`,
        `[data-notification-type-id="${definition.code}"]`,
        `.d-icon-${definition.icon}`,
        `[href$="#${definition.icon}"]`,
      ].join(",");
      document.querySelectorAll(selectors).forEach((marker) => {
        const item = getNotificationItem(marker);
        if (item) {
          matchedItems.set(item, definition);
        }
      });
    });

    document.querySelectorAll(".ldo-follow-notification").forEach((item) => {
      if (!matchedItems.has(item)) {
        item.classList.remove(
          "ldo-follow-notification",
          "ldo-follow-notification-topic",
          "ldo-follow-notification-reply",
          "ldo-follow-notification-follower"
        );
        item.querySelectorAll(".ldo-follow-notification-label").forEach((label) => label.remove());
      }
    });

    matchedItems.forEach((definition, item) => {
      if (item.classList.contains(definition.className)) {
        return;
      }
      item.classList.remove(
        "ldo-follow-notification-topic",
        "ldo-follow-notification-reply",
        "ldo-follow-notification-follower"
      );
      item.classList.add("ldo-follow-notification", definition.className);

      const labelHost =
        item.querySelector(".notification-description, .text, .excerpt") ||
        item.querySelector("a") ||
        item;
      let label = item.querySelector(".ldo-follow-notification-label");
      if (!label) {
        label = createElement("span", "ldo-follow-notification-label");
        labelHost.appendChild(label);
      }
      if (label.textContent !== definition.label) {
        label.textContent = definition.label;
      }
    });
  }

  function getNotificationItem(marker) {
    if (marker.matches("[data-notification-type], [data-notification-type-id]")) {
      return marker;
    }
    return marker.closest(
      "[data-notification-id], .notification-list-item, .notification-item, .user-notifications-list-item, li"
    );
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

  function getTopicRowAuthorUsernames(row) {
    return Array.from(new Set(getTopicRowAuthorElements(row).map(getDomUsername).filter(Boolean)));
  }

  function getTopicRowAuthorElements(row) {
    const posterElements = Array.from(
      row.querySelectorAll(
        ".posters [data-user-card], .topic-list-posters [data-user-card], .topic-users [data-user-card]"
      )
    );
    if (!posterElements.length) {
      return [];
    }

    const originalPosters = posterElements.filter((element) => {
      const description = [
        element.getAttribute("title"),
        element.getAttribute("aria-label"),
        element.getAttribute("data-title"),
        element.className,
      ]
        .filter(Boolean)
        .join(" ");
      return /original poster|topic owner|主题作者|楼主|原始发帖人/i.test(description);
    });
    return originalPosters.length ? originalPosters : posterElements.slice(0, 1);
  }

  function getPostAuthorUsername(post) {
    return getDomUsername(getPostAuthorElement(post));
  }

  function getPostAuthorElement(post) {
    return post.querySelector(
      ":scope > article .names [data-user-card], :scope > article [data-user-card].trigger-user-card, :scope > article [data-username]"
    );
  }

  function getDomUsername(element) {
    if (!element) {
      return "";
    }

    const directUsername =
      element.getAttribute("data-user-card") ||
      element.getAttribute("data-username") ||
      element.dataset?.userCard ||
      element.dataset?.username;
    if (directUsername) {
      return normalizeUsername(directUsername);
    }

    const href = element.getAttribute("href") || "";
    const match = href.match(/\/u\/([^/?#]+)/i);
    return match ? normalizeUsername(decodeURIComponent(match[1])) : "";
  }

  function isTopicRowFollowed(row, topicRelations, followedUsers) {
    if (readBooleanFromDom(row, FOLLOWED_AUTHOR_KEYS)) {
      return true;
    }

    const topicId = getTopicRowId(row);
    const relation = topicId ? topicRelations.get(topicId) : null;
    if (relation?.followed) {
      return true;
    }

    const authorUsernames = new Set([
      ...(relation?.authorUsernames || []),
      ...getTopicRowAuthorUsernames(row),
    ]);
    return Array.from(authorUsernames).some((username) => followedUsers.has(username));
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

  function isPostFollowed(post, relation, followedUsers) {
    if (Boolean(relation?.followed) || readBooleanFromDom(post, FOLLOWED_AUTHOR_KEYS)) {
      return true;
    }

    const username = normalizeUsername(relation?.username || getPostAuthorUsername(post));
    return Boolean(username && followedUsers.has(username));
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
        authorUsernames: getTopicModelAuthorUsernames(topic),
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
    return getTopicAuthorModels(topic).some((author) =>
      readBooleanFromKeys(author, FOLLOWED_AUTHOR_KEYS)
    );
  }

  function getTopicModelAuthorUsernames(topic) {
    return Array.from(
      new Set(getTopicAuthorModels(topic).map(getModelUsername).filter(Boolean))
    );
  }

  function getTopicAuthorModels(topic) {
    const posters = toArray(readValue(topic, ["posters", "participants"]));
    const originalPosters = posters.filter(isOriginalPosterModel);
    const selectedPosters = originalPosters.length ? originalPosters : posters.slice(0, 1);
    const directAuthors = [
      readValue(topic, ["creator"]),
      readValue(topic, ["original_poster", "originalPoster"]),
      readValue(topic, ["first_poster", "firstPoster"]),
    ].filter(Boolean);

    const authors = [...directAuthors, ...selectedPosters];
    authors.forEach((author) => {
      const user = readValue(author, ["user", "author"]);
      if (user) {
        authors.push(user);
      }
    });
    return Array.from(new Set(authors));
  }

  function isOriginalPosterModel(poster) {
    if (
      readBooleanFromKeys(poster, [
        "original_poster",
        "originalPoster",
        "is_original_poster",
        "isOriginalPoster",
      ])
    ) {
      return true;
    }

    const description = [
      readValue(poster, ["description"]),
      readValue(poster, ["extras"]),
      readValue(poster, ["title"]),
    ]
      .filter(Boolean)
      .join(" ");
    return /original poster|topic owner|主题作者|楼主|原始发帖人/i.test(description);
  }

  function getModelUsername(model) {
    const direct = readValue(model, ["username", "user_name", "userName"]);
    if (direct) {
      return normalizeUsername(direct);
    }

    const user = readValue(model, ["user", "author"]);
    return user ? normalizeUsername(readValue(user, ["username", "user_name", "userName"])) : "";
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

  const SVG_ARROW_UP =
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5l7 7-1.4 1.4L13 8.8V19h-2V8.8L6.4 13.4 5 12z"/></svg>';
  const SVG_ARROW_DOWN =
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 19l-7-7 1.4-1.4L11 15.2V5h2v10.2l4.6-4.6L19 12z"/></svg>';

  function enhanceCodeBlocks() {
    if (!state.config.features.codeCopy) {
      document.querySelectorAll(".ldo-code-copy-btn").forEach((btn) => btn.remove());
      document.querySelectorAll("[data-ldo-code-copy]").forEach((pre) => delete pre.dataset.ldoCodeCopy);
      return;
    }

    document.querySelectorAll(".cooked pre").forEach((pre) => {
      if (pre.dataset.ldoCodeCopy === "1") {
        return;
      }
      pre.dataset.ldoCodeCopy = "1";
      const button = createElement("button", "ldo-code-copy-btn", "复制");
      button.type = "button";
      button.setAttribute("aria-label", "复制代码");
      button.addEventListener("click", (event) => handleCodeCopyClick(event, pre, button));
      pre.appendChild(button);
    });
  }

  async function handleCodeCopyClick(event, pre, button) {
    event.stopPropagation();
    event.preventDefault();
    const source = pre.querySelector("code") || pre;
    const text = source.innerText || source.textContent || "";
    const succeeded = await copyTextToClipboard(text);
    button.classList.toggle("ldo-copied", succeeded);
    button.textContent = succeeded ? "已复制" : "复制失败";
    window.clearTimeout(button.__ldoResetTimer);
    button.__ldoResetTimer = window.setTimeout(() => {
      button.classList.remove("ldo-copied");
      button.textContent = "复制";
    }, 1600);
  }

  async function copyTextToClipboard(text) {
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(text);
        return true;
      }
    } catch {
    }
    try {
      const textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.setAttribute("readonly", "true");
      textarea.style.position = "fixed";
      textarea.style.top = "-9999px";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();
      const succeeded = document.execCommand("copy");
      textarea.remove();
      return succeeded;
    } catch {
      return false;
    }
  }

  function enhanceLongImages() {
    if (!state.config.features.longImage) {
      document.querySelectorAll(".ldo-long-image").forEach((wrapper) => {
        const img = wrapper.querySelector("img");
        if (img && wrapper.parentNode) {
          wrapper.parentNode.insertBefore(img, wrapper);
        }
        wrapper.remove();
      });
      document.querySelectorAll("img[data-ldo-long-image]").forEach((img) => {
        delete img.dataset.ldoLongImage;
      });
      return;
    }

    document
      .querySelectorAll(".cooked img:not(.emoji):not(.d-emoji):not(.avatar):not([data-ldo-long-image])")
      .forEach((img) => {
        if (img.closest(".ldo-long-image") || img.closest("a.lightbox")) {
          return;
        }
        img.dataset.ldoLongImage = "1";
        if (img.complete && img.naturalHeight) {
          tryWrapLongImage(img);
        } else {
          img.addEventListener("load", () => tryWrapLongImage(img), { once: true });
        }
      });
  }

  function tryWrapLongImage(img) {
    if (!img.isConnected || img.naturalHeight <= LONG_IMAGE_MIN_HEIGHT) {
      return;
    }
    const parent = img.parentElement;
    if (!parent || parent.classList.contains("ldo-long-image")) {
      return;
    }
    const wrapper = document.createElement("span");
    wrapper.className = "ldo-long-image";
    wrapper.dataset.ldoHint = "点击展开长图";
    parent.insertBefore(wrapper, img);
    wrapper.appendChild(img);
    wrapper.addEventListener("click", (event) => {
      if (event.metaKey || event.ctrlKey || event.shiftKey) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      const expanded = wrapper.classList.toggle("ldo-expanded");
      wrapper.dataset.ldoHint = expanded ? "点击收起" : "点击展开长图";
    });
  }

  function enhanceQuotes() {
    if (!state.config.features.quoteCollapse) {
      document.querySelectorAll("aside.quote.ldo-quote-collapsible").forEach((quote) => {
        quote.classList.remove("ldo-quote-collapsible", "ldo-quote-collapsed");
        delete quote.dataset.ldoQuote;
      });
      return;
    }

    document.querySelectorAll(".cooked aside.quote").forEach((quote) => {
      if (quote.dataset.ldoQuote === "1") {
        return;
      }
      const title = quote.querySelector(":scope > .title");
      const blockquote = quote.querySelector(":scope > blockquote");
      if (!title || !blockquote) {
        return;
      }
      quote.dataset.ldoQuote = "1";
      quote.classList.add("ldo-quote-collapsible");
      const nested = quote.parentElement?.closest("aside.quote");
      const isLong = blockquote.offsetHeight > QUOTE_COLLAPSE_MIN_HEIGHT;
      if (nested || isLong) {
        quote.classList.add("ldo-quote-collapsed");
      }
      title.addEventListener("click", (event) => {
        if (!quote.classList.contains("ldo-quote-collapsible")) {
          return;
        }
        if (event.target.closest(".quote-controls")) {
          return;
        }
        quote.classList.toggle("ldo-quote-collapsed");
      });
    });
  }

  function enhanceTopicBadges() {
    const enabled = state.config.features.topicBadges;
    document.querySelectorAll(".topic-list-item, .latest-topic-list-item, .category-topic-link").forEach((row) => {
      const badges = enabled ? detectTopicBadges(row) : [];
      applyTopicBadges(row, badges);
    });
  }

  function detectTopicBadges(row) {
    const badges = [];
    const kinds = new Set();
    const add = (kind, label) => {
      if (kinds.has(kind)) {
        return;
      }
      kinds.add(kind);
      badges.push({ kind, label });
    };

    if (
      row.matches(".status-solved, .accepted-answer, [data-topic-solved='true']") ||
      row.querySelector(
        ".topic-status .d-icon-square-check, .topic-status .d-icon-check-square, .topic-status .d-icon-circle-check, .topic-statuses .d-icon-square-check"
      )
    ) {
      add("solved", "已解决");
    }

    if (row.matches(".pinned") || row.querySelector(".topic-status .d-icon-thumbtack")) {
      add("pinned", "置顶");
    }

    if (
      row.matches(".closed, .archived") ||
      row.querySelector(".topic-status .d-icon-lock, .topic-status .d-icon-envelope")
    ) {
      add("closed", "已关闭");
    }

    row.querySelectorAll(".discourse-tag").forEach((tag) => {
      const name = (tag.getAttribute("data-tag-name") || tag.textContent || "").trim();
      if (!name) {
        return;
      }
      if (/精华|feature|essence/i.test(name)) {
        add("featured", "精华");
      }
      if (/抽奖|giveaway|lottery|福利/i.test(name)) {
        add("giveaway", "抽奖");
      }
      if (/^hot$|热门|热议/i.test(name)) {
        add("hot", "热门");
      }
    });

    return badges;
  }

  function applyTopicBadges(row, badges) {
    const container = row.querySelector(":scope .ldo-topic-badges");
    const key = badges.map((b) => b.kind).join(",");

    if (!badges.length) {
      container?.remove();
      return;
    }

    const anchor =
      row.querySelector(":scope .main-link .title") ||
      row.querySelector(":scope a.title") ||
      row.querySelector(":scope .main-link a[href*='/t/']");
    if (!anchor) {
      return;
    }

    let host = container;
    if (!host) {
      host = createElement("span", "ldo-topic-badges");
      anchor.after(host);
    }

    if (host.dataset.ldoBadgeKey === key) {
      return;
    }
    host.dataset.ldoBadgeKey = key;
    host.textContent = "";
    badges.forEach(({ kind, label }) => {
      host.appendChild(createElement("span", `ldo-topic-badge ldo-topic-badge-${kind}`, label));
    });
  }

  function initFloatingActions() {
    if (state.floatingActionsRoot || !document.body) {
      return;
    }
    const container = createElement("div", "ldo-floating-actions");
    container.setAttribute("aria-hidden", "true");

    const topBtn = createFloatingButton("回到顶部", SVG_ARROW_UP);
    topBtn.addEventListener("click", () => {
      window.scrollTo({ top: 0, behavior: "smooth" });
    });

    const bottomBtn = createFloatingButton("回到底部", SVG_ARROW_DOWN);
    bottomBtn.addEventListener("click", () => {
      const target = Math.max(
        document.documentElement.scrollHeight,
        document.body.scrollHeight
      );
      window.scrollTo({ top: target, behavior: "smooth" });
    });

    container.append(topBtn, bottomBtn);
    document.body.appendChild(container);
    state.floatingActionsRoot = container;
  }

  function createFloatingButton(label, svg) {
    const button = createElement("button", "ldo-floating-btn");
    button.type = "button";
    button.setAttribute("aria-label", label);
    button.title = label;
    button.innerHTML = svg;
    return button;
  }

  function updateFloatingActionsVisibility() {
    const container = state.floatingActionsRoot;
    if (!container) {
      return;
    }
    if (!state.config.features.floatingActions) {
      container.classList.remove("ldo-visible");
      return;
    }
    const shouldShow = window.scrollY > 320;
    container.classList.toggle("ldo-visible", shouldShow);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
