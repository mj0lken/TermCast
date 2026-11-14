(() => {
  const copyBtn = document.getElementById("copy-btn");
  const buildCmd = document.getElementById("build-cmd");

  if (copyBtn && buildCmd && navigator.clipboard) {
    copyBtn.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(buildCmd.textContent || "");
        copyBtn.textContent = "Copied";
        window.setTimeout(() => {
          copyBtn.textContent = "Copy";
        }, 1600);
      } catch {
        copyBtn.textContent = "Failed";
      }
    });
  }

  const downloadCta = document.getElementById("download-cta");
  const downloadLabel = document.getElementById("download-label");

  if (downloadCta && downloadLabel) {
    fetch("https://api.github.com/repos/mj0lken/TermCast/releases/latest", {
      headers: { Accept: "application/vnd.github+json" },
    })
      .then((res) => (res.ok ? res.json() : null))
      .then((release) => {
        if (!release || !Array.isArray(release.assets)) return;
        const dmg =
          release.assets.find(
            (a) =>
              typeof a.name === "string" &&
              a.name.endsWith(".dmg") &&
              !a.name.includes("Universal")
          ) ||
          release.assets.find(
            (a) => typeof a.name === "string" && a.name.endsWith(".dmg")
          );
        if (dmg && typeof dmg.browser_download_url === "string") {
          downloadCta.setAttribute("href", dmg.browser_download_url);
        }
        if (typeof release.tag_name === "string" && release.tag_name.length > 0) {
          downloadLabel.textContent = `Download ${release.tag_name}`;
        }
      })
      .catch(() => {});
  }
})();
