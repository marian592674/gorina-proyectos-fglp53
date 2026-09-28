// Cliente HTTP asíncrono para el Tablero Analítico Carnicería Gorina

const API = {
  baseUrl: '',
  cache: new Map(),

  buildQuery(params) {
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) {
      if (v !== '' && v !== null && v !== undefined) {
        if (Array.isArray(v)) {
          v.forEach(item => {
            if (item !== '' && item !== null && item !== undefined) {
              q.append(k, item);
            }
          });
        } else {
          q.append(k, v);
        }
      }
    }
    return q.toString();
  },

  clearCache() {
    this.cache.clear();
  },

  async request(endpoint, params = {}) {
    const qs = this.buildQuery(params);
    const url = `${this.baseUrl}/api/${endpoint}${qs ? '?' + qs : ''}`;
    
    // Caché en memoria de cliente (TTL 45 segundos)
    if (this.cache.has(url)) {
      const entry = this.cache.get(url);
      if (Date.now() - entry.time < 45000) {
        return entry.data;
      }
    }

    const res = await fetch(url, { cache: 'no-store' });
    if (!res.ok) {
      throw new Error(`Error ${res.status}: ${res.statusText}`);
    }
    const data = await res.json();

    if (this.cache.size > 300) {
      const first = this.cache.keys().next().value;
      this.cache.delete(first);
    }
    this.cache.set(url, { data, time: Date.now() });

    return data;
  },

  async getFiltros(params = {}) {
    return await this.request('filtros', params);
  },

  async getOpcionesClientes(q = '') {
    return await this.request('opciones_clientes', { q });
  },

  async getOpcionesMateriales(q = '') {
    return await this.request('opciones_materiales', { q });
  },

  async getKPIs(filters) {
    return await this.request('kpis', filters);
  },

  async getEvolucion(filters, modo = 'mes') {
    return await this.request('evolucion', { ...filters, modo });
  },

  async getRanking(filters, dim = 'apertura', limit = 15) {
    return await this.request('ranking', { ...filters, dim, limit });
  },

  async getDrilldown(filters) {
    return await this.request('drilldown', filters);
  },

  async getDetalle(filters, page = 1, limit = 50, sort = 'fecha', dir = 'DESC') {
    return await this.request('detalle', { ...filters, page, limit, sort, dir });
  },

  async getCalidad() {
    return await this.request('calidad');
  },

  async getEstado() {
    return await this.request('estado');
  }
};
