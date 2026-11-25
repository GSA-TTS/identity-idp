document.querySelectorAll<HTMLElement>('[data-form-tabs]').forEach((container) => {
  const tabs = container.querySelectorAll<HTMLElement>('[role="tab"]');
  const panels = container.querySelectorAll<HTMLElement>('[role="tabpanel"]');

  tabs.forEach((tab) => {
    const tabId = tab.id.split('-').pop();

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
      const panel = container.querySelector<HTMLElement>(`#panel-${tabId}`);

      if (panel) {
        panel.hidden = false;
        const fieldset = panel.querySelector<HTMLFieldSetElement>('fieldset');
        if (fieldset) {
          fieldset.disabled = false;
        }
      }
    });
  });
});
