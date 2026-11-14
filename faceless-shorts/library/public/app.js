const state = { videos: [], query: '' };
const $ = (selector) => document.querySelector(selector);
const grid = $('#grid');
const featured = $('#featured');
const empty = $('#empty');
const count = $('#count');
const template = $('#card-template');
const dialog = $('#player-dialog');
const player = $('#player');

function date(value) {
  return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', year: 'numeric' }).format(new Date(value));
}
function size(bytes) {
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(bytes >= 100 * 1024 * 1024 ? 0 : 1)} MB`;
}
function matches(video) {
  const haystack = [video.title, video.project, video.style, video.projectPath].join(' ').toLowerCase();
  return haystack.includes(state.query);
}
function open(video) {
  player.src = video.videoUrl;
  player.poster = video.posterUrl || '';
  $('#dialog-style').textContent = video.style;
  $('#dialog-title').textContent = video.title;
  $('#dialog-details').textContent = `${date(video.createdAt)} · ${size(video.size)} · ${video.projectPath}`;
  dialog.showModal();
  player.play().catch(() => {});
}
function setBackground(button, video) {
  button.style.backgroundImage = video.posterUrl
    ? `linear-gradient(0deg, rgba(6,8,15,.8), rgba(6,8,15,.05) 65%), url("${video.posterUrl}")`
    : 'linear-gradient(135deg, #252c45, #0b0e17)';
}
function renderFeatured(video) {
  if (!video || state.query) { featured.classList.add('hidden'); featured.innerHTML = ''; return; }
  featured.classList.remove('hidden');
  featured.innerHTML = `
    <button class="feature-art" type="button" aria-label="Play ${video.title}"><span class="large-play">▶</span></button>
    <div class="feature-copy"><p class="eyebrow">LATEST RENDER <span>•</span> ${date(video.createdAt)}</p><h2>${video.title}</h2><p>${video.style} <span>·</span> ${size(video.size)}</p><button class="watch" type="button">Watch now <b>→</b></button></div>`;
  const art = featured.querySelector('.feature-art');
  setBackground(art, video);
  art.addEventListener('click', () => open(video));
  featured.querySelector('.watch').addEventListener('click', () => open(video));
}
function render() {
  const videos = state.videos.filter(matches);
  grid.innerHTML = '';
  count.textContent = `${videos.length} ${videos.length === 1 ? 'video' : 'videos'}`;
  empty.classList.toggle('hidden', videos.length !== 0 || state.videos.length !== 0);
  renderFeatured(videos[0]);
  videos.forEach((video, index) => {
    const node = template.content.cloneNode(true);
    const article = node.querySelector('.card');
    const button = node.querySelector('.thumbnail');
    node.querySelector('.style').textContent = video.style;
    node.querySelector('h2').textContent = video.title;
    node.querySelector('.meta').textContent = `${date(video.createdAt)}  ·  ${size(video.size)}`;
    article.style.setProperty('--delay', `${Math.min(index, 12) * 45}ms`);
    setBackground(button, video);
    button.addEventListener('click', () => open(video));
    grid.append(node);
  });
}
async function load() {
  const button = $('#refresh');
  button.disabled = true;
  button.classList.add('spinning');
  try {
    const response = await fetch('/api/videos');
    if (!response.ok) throw new Error('Could not load the library.');
    state.videos = (await response.json()).videos;
    render();
  } catch (error) {
    count.textContent = error.message;
  } finally {
    button.disabled = false;
    button.classList.remove('spinning');
  }
}
$('#search').addEventListener('input', (event) => { state.query = event.target.value.trim().toLowerCase(); render(); });
$('#refresh').addEventListener('click', load);
dialog.querySelector('.close').addEventListener('click', () => dialog.close());
dialog.addEventListener('close', () => { player.pause(); player.removeAttribute('src'); player.load(); });
load();
