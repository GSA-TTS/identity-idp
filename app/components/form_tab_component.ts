const tabs = document.querySelectorAll<HTMLElement>('[role="tab"]');
const panels = document.querySelectorAll<HTMLElement>('[role="tabpanel"]');

tabs.forEach((tab) => {
  tab.addEventListener('click', () => {
    tabs.forEach((t) => {
      t.classList.add('usa-button--outline');
    });

    panels.forEach((panel) => {
      panel.hidden = true;
      const fieldset = panel.querySelector<HTMLFieldSetElement>('fieldset');
      if (fieldset) {
        fieldset.disabled = true;
      }
    });

    tab.classList.remove('usa-button--outline');
    const panel = document.querySelector<HTMLElement>(`#panel-${tab.id.split('-').pop()}`);

    if (panel) {
      panel.hidden = false;
      const fieldset = panel.querySelector<HTMLFieldSetElement>('fieldset');
      if (fieldset) {
        fieldset.disabled = false;
      }
    }
  });
});
