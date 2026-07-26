document.addEventListener("DOMContentLoaded", function () {
  const sidebarLists = document.querySelectorAll(
    ".hextra-sidebar-container .hextra-scrollbar > ul"
  );
  const desktopList = Array.from(sidebarLists).find(function (list) {
    return list.classList.contains("hx:max-md:hidden");
  });

  if (!desktopList || desktopList.dataset.cosmosDocsGroup) {
    return;
  }

  const firstLink = desktopList.querySelector(":scope > li a");
  if (!firstLink) {
    return;
  }

  const childList = document.createElement("ul");
  childList.className =
    'hx:relative hx:flex hx:flex-col hx:gap-1 hx:before:absolute hx:before:inset-y-1 hx:before:w-px hx:before:bg-gray-200 hx:before:content-[""] hx:ltr:ml-3 hx:ltr:pl-3 hx:ltr:before:left-0 hx:rtl:mr-3 hx:rtl:pr-3 hx:rtl:before:right-0 hx:dark:before:bg-neutral-800';
  childList.append(...desktopList.children);

  const section = document.createElement("li");
  section.className = "open";
  section.innerHTML = `
    <div class="hextra-sidebar-item hx:group hx:relative hx:flex hx:items-center">
      <a class="hx:flex hx:items-center hx:justify-between hx:gap-2 hx:grow hx:cursor-pointer hx:rounded-sm hx:px-2 hx:py-1.5 hx:text-sm hx:transition-colors [-webkit-tap-highlight-color:transparent] [-webkit-touch-callout:none] hx:hextra-focus-visible-inset hx:ltr:pr-8 hx:rtl:pl-8 hx:text-gray-500 hx:hover:bg-gray-100 hx:hover:text-gray-900 hx:dark:text-neutral-400 hx:dark:hover:bg-primary-100/5 hx:dark:hover:text-gray-50" href="${new URL("../", firstLink.href).pathname}">
        <span class="hx:min-w-0 [word-break:break-word]">Documentation</span>
      </a>
      <button type="button" class="hextra-sidebar-collapsible-button hx:absolute hx:top-1/2 hx:-translate-y-1/2 hx:ltr:right-2 hx:rtl:left-2 hx:shrink-0 hx:cursor-pointer hx:p-0 hx:text-gray-500 hx:dark:text-neutral-400 hx:group-hover:text-gray-900 hx:dark:group-hover:text-gray-50 hx:hextra-focus-visible-inset" aria-label="Toggle section" aria-expanded="true">
        <svg fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true" focusable="false" class="hx:h-[18px] hx:min-w-[18px] hx:rounded-xs hx:p-0.5 hx:hover:bg-gray-800/5 hx:dark:hover:bg-gray-100/5"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" class="hx:origin-center hx:transition-transform hx:rtl:-rotate-180"></path></svg>
      </button>
    </div>
    <div class="hextra-sidebar-children hx:ltr:pr-0 hx:rtl:pl-0 hx:overflow-hidden"></div>
  `;
  section.querySelector(".hextra-sidebar-children").appendChild(childList);

  desktopList.appendChild(section);
  desktopList.dataset.cosmosDocsGroup = "true";
});
