// The marker: a tab whose title names the command that fired and which of
// Chrome's panel APIs this browser offers, so a run can read the answer
// off the sidebar.
chrome.commands.onCommand.addListener((command) => {
  const title = `${command} sidePanel=${typeof chrome.sidePanel} notifications=${typeof chrome.notifications} sidebarAction=${typeof chrome.sidebarAction}`;
  chrome.tabs.create({ url: `data:text/html,<title>${encodeURIComponent(title)}</title>${encodeURIComponent(title)}` });
});
