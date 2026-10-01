import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const run=promisify(execFile);

// Invoked only by the user's Paste action. CP437 clipboard APIs lose Chinese.
export async function readClipboardText() {
  if(process.platform!=='win32') throw new Error('clipboard unavailable');
  const {stdout}=await run('powershell.exe',['-NoProfile','-NonInteractive','-Command',
    '[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); $promptClipboard = Get-Clipboard -Raw; if ($null -ne $promptClipboard) { [Console]::Write($promptClipboard) }'],
    {windowsHide:true,timeout:3000,maxBuffer:65536,encoding:'utf8'});
  return stdout.replace(/\r\n?/g,'\n');
}
