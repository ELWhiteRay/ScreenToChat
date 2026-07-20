import Foundation

enum ChatGPTDOM {
    static let openPreparedChat = """
    (async () => {
      const preferredTitle = 'Ждать скриншот задания';
      let selectedRow = null;
      for (let attempt = 0; attempt < 48; attempt++) {
        const rows = [...document.querySelectorAll('[data-app-action-sidebar-thread-row]')];
        selectedRow ||= rows.find(item =>
            item.dataset.appActionSidebarThreadTitle === preferredTitle
          ) || rows.find(item =>
            (item.dataset.appActionSidebarThreadTitle || '').startsWith('Ждать скриншот')
          );
        if (selectedRow) {
          if (selectedRow.dataset.appActionSidebarThreadActive !== 'true') selectedRow.click();
          const active = selectedRow.dataset.appActionSidebarThreadActive === 'true';
          const composer = document.querySelector('[data-codex-composer=true]');
          const hasHistory = document.querySelector('[data-turn-key]');
          if (active && composer && hasHistory) {
            return `opened:${selectedRow.dataset.appActionSidebarThreadTitle || preferredTitle}`;
          }
        }
        await new Promise(resolve => setTimeout(resolve, 250));
      }
      return selectedRow ? 'not-ready' : 'missing';
    })()
    """

    static func attachImage(filename: String, base64: String) -> String {
        """
        (async () => {
          const target = document.querySelector('[data-codex-composer=true]');
          if (!target) return 'missing-composer';
          const staleAttachments = [...document.querySelectorAll(
            'button[aria-label^="Remove screen-to-chat-"]'
          )];
          staleAttachments.forEach(button => button.click());
          if (staleAttachments.length) {
            await new Promise(resolve => setTimeout(resolve, 250));
          }
          const binary = atob('\(base64)');
          const bytes = Uint8Array.from(binary, character => character.charCodeAt(0));
          const file = new File([bytes], '\(filename)', {type: 'image/png'});
          const transfer = new DataTransfer();
          transfer.items.add(file);
          for (const type of ['dragenter', 'dragover', 'drop']) {
            target.dispatchEvent(new DragEvent(type, {
              bubbles: true, cancelable: true, dataTransfer: transfer
            }));
          }
          for (let attempt = 0; attempt < 20; attempt++) {
            if (document.querySelector('button[aria-label="Remove \(filename)"]')) return 'attached';
            await new Promise(resolve => setTimeout(resolve, 250));
          }
          return 'missing-attachment';
        })()
        """
    }

}
