const state = {
  garageName: "",
  garageLabel: "",
  accessPoint: 1,
  vehicles: [],
  loadingId: null,
  search: ""
};

const STATUS = {
  stored: { label: "Stored", tone: "text-cyan", dot: "bg-cyan" },
  out: { label: "Out in world", tone: "text-violet-300", dot: "bg-violet-300" },
  impounded: { label: "Impounded", tone: "text-amber-300", dot: "bg-amber-300" }
};

const post = async (name, payload = {}) => {
  const response = await fetch(`https://${GetParentResourceName()}/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify(payload)
  });
  return response.json();
};

const escapeHtml = (value) => String(value ?? "").replace(/[&<>'"]/g, (character) => ({
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  "'": "&#039;",
  "\"": "&quot;"
}[character]));

const showNotice = (message) => {
  const notice = document.querySelector("#notice");
  notice.textContent = message;
  notice.classList.remove("hidden");
};

const render = () => {
  const grid = document.querySelector("#vehicleGrid");
  const searchTerm = state.search.trim().toLowerCase();
  const visibleVehicles = state.vehicles.filter((vehicle) => `${vehicle.brand} ${vehicle.name} ${vehicle.modelName} ${vehicle.plate}`.toLowerCase().includes(searchTerm));
  const outCount = state.vehicles.filter((vehicle) => vehicle.status === "out").length;

  document.querySelector("#garageName").textContent = state.garageLabel;
  document.querySelector("#fleetCount").textContent = state.vehicles.length;
  document.querySelector("#outCount").textContent = outCount;

  if (visibleVehicles.length === 0) {
    grid.innerHTML = `<div class="col-span-full flex min-h-64 flex-col items-center justify-center rounded-2xl border border-dashed border-white/10 bg-white/[0.02] text-center"><div class="mb-4 text-4xl text-white/15">◌</div><p class="font-display text-sm text-white/60">No vehicles found</p><p class="mt-2 text-xs text-white/30">Try another search or check a different collection.</p></div>`;
    return;
  }

  grid.innerHTML = visibleVehicles.map((vehicle, index) => {
    const status = STATUS[vehicle.status] || STATUS.stored;
    const isLoading = state.loadingId === vehicle.id;
    const disabled = !vehicle.canRetrieve || isLoading;
    const buttonText = isLoading ? "Connecting..." : vehicle.canRetrieve ? vehicle.status === "out" ? "Respawn vehicle" : "Take out" : "Visit impound";
    const actionClass = vehicle.canRetrieve ? "border-cyan/30 bg-cyan/10 text-cyan hover:border-cyan/60 hover:bg-cyan/20" : "cursor-not-allowed border-white/10 bg-white/[0.03] text-white/30";

    return `<article class="vehicle-card group flex flex-col rounded-2xl border border-white/10 bg-white/[0.035] p-4 transition duration-200 hover:-translate-y-1 hover:border-white/20 hover:bg-white/[0.06]" style="animation-delay: ${index * 35}ms"><div class="mb-5 flex items-start justify-between"><div class="flex h-11 w-11 items-center justify-center rounded-xl border border-white/10 bg-gradient-to-br from-white/10 to-white/[0.02] font-display text-lg text-white/60">${escapeHtml(vehicle.name.slice(0, 1).toUpperCase())}</div><span class="flex items-center gap-2 rounded-full border border-white/10 bg-black/20 px-2.5 py-1 text-[10px] uppercase tracking-[0.12em] ${status.tone}"><span class="h-1.5 w-1.5 rounded-full ${status.dot}"></span>${status.label}</span></div><div class="min-h-[4.5rem]"><p class="text-[10px] uppercase tracking-[0.16em] text-white/30">${escapeHtml(vehicle.brand)}</p><h3 class="mt-1 truncate font-display text-base text-white">${escapeHtml(vehicle.name)}</h3><p class="mt-2 font-mono text-[11px] tracking-[0.18em] text-white/35">${escapeHtml(vehicle.plate)}</p></div><div class="mt-5 grid grid-cols-3 gap-2 border-t border-white/10 pt-4"><div><p class="text-[9px] uppercase tracking-wider text-white/25">Fuel</p><p class="mt-1 text-xs text-white/65">${vehicle.fuel}%</p></div><div><p class="text-[9px] uppercase tracking-wider text-white/25">Engine</p><p class="mt-1 text-xs text-white/65">${vehicle.engine}%</p></div><div><p class="text-[9px] uppercase tracking-wider text-white/25">Body</p><p class="mt-1 text-xs text-white/65">${vehicle.body}%</p></div></div><button type="button" data-action="retrieve" data-id="${vehicle.id}" class="mt-5 w-full rounded-xl border px-3 py-2.5 text-xs font-semibold transition ${actionClass}" ${disabled ? "disabled" : ""}>${buttonText}${vehicle.status === "out" && vehicle.canRetrieve ? `<span class="ml-2 text-cyan/50">↗</span>` : ""}</button></article>`;
  }).join("");
};

const closeUI = () => {
  post("close");
};

const retrieveVehicle = async (vehicleId) => {
  const vehicle = state.vehicles.find((entry) => entry.id === vehicleId);
  if (!vehicle || !vehicle.canRetrieve || state.loadingId !== null) return;

  state.loadingId = vehicleId;
  document.querySelector("#notice").classList.add("hidden");
  render();

  try {
    const result = await post("retrieve", { vehicleId, garageName: state.garageName, accessPoint: state.accessPoint });
    if (!result || result.ok !== true) {
      showNotice(result?.error || "The vehicle could not be retrieved.");
      return;
    }
    closeUI();
  } catch (_error) {
    showNotice("The garage connection failed. Please try again.");
  } finally {
    state.loadingId = null;
    render();
  }
};

window.addEventListener("message", (event) => {
  const { action, data } = event.data;
  if (action === "open") {
    state.garageName = data.garageName;
    state.garageLabel = data.garageLabel;
    state.accessPoint = data.accessPoint;
    state.vehicles = data.vehicles || [];
    state.loadingId = null;
    state.search = "";
    document.querySelector("#search").value = "";
    document.querySelector("#notice").classList.add("hidden");
    document.body.classList.remove("opacity-0", "pointer-events-none");
    document.body.classList.add("opacity-100", "pointer-events-auto");
    render();
  }
  if (action === "close") {
    document.body.classList.add("opacity-0", "pointer-events-none");
    document.body.classList.remove("opacity-100", "pointer-events-auto");
  }
});

document.querySelector("#vehicleGrid").addEventListener("click", (event) => {
  const button = event.target.closest("[data-action=retrieve]");
  if (button) retrieveVehicle(Number(button.dataset.id));
});

document.querySelector("#search").addEventListener("input", (event) => {
  state.search = event.target.value;
  render();
});

document.querySelector("#closeButton").addEventListener("click", closeUI);
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeUI();
});
