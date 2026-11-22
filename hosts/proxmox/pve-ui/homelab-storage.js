// Managed by the homelab inventory repo: hosts/proxmox/pve-ui/homelab-storage.js
// Adds a "Storage (Smart Array)" panel to each node Summary. This file holds code only.
// The data comes from the node Notes through the API, so only logged-in users see it.
// The collector hosts/proxmox/storage-monitoring/homelab-smart-array-collect writes that data.
(function () {
    'use strict';

    const MARKER = 'homelab-smart-array-json';
    const REFRESH_MS = 60 * 1000;
    const SCAN_MS = 1500;
    const GRAFANA = 'https://grafana.cf.lcamaral.com/d/proxmox-smart-array';

    const enc = (v) => Ext.htmlEncode(v === null || v === undefined ? '-' : String(v));
    const badge = (ok, text) =>
        `<span style="padding:1px 6px;border-radius:3px;color:#fff;background:${ok ? '#2e7d32' : '#c62828'}">${enc(text)}</span>`;

    function parseNotes(description) {
        const match = new RegExp(`<!-- ${MARKER} (\\{.*?\\}) -->`, 's').exec(description || '');
        return match ? JSON.parse(match[1]) : null;
    }

    function render(data) {
        if (!data) {
            return '<i>No Smart Array data in the node Notes yet. Check homelab-smart-array-collect.timer.</i>';
        }
        const c = data.controller;
        const age = Math.round((Date.now() / 1000 - data.time) / 60);
        const nbwc = c.nbwc
            ? `<span style="padding:1px 6px;border-radius:3px;color:#000;background:#ffa726">Enabled</span>`
            : badge(true, 'Disabled');
        const head = `<div style="margin-bottom:6px">${enc(c.model)} &middot; Controller ${badge(c.controller === 'OK', c.controller)}`
            + ` Cache ${badge(c.cache === 'OK', c.cache)} Capacitor ${badge(c.capacitor === 'OK', c.capacitor)}`
            + ` Write cache without capacitor ${nbwc}`
            + ` &middot; <span style="opacity:.7">updated ${age} min ago</span>`
            + ` &middot; <a href="${GRAFANA}" target="_blank" rel="noopener">Grafana</a></div>`;
        const cell = 'style="padding:2px 8px;text-align:left"';
        const vols = data.volumes.map((v) =>
            `<tr><td ${cell}>${enc(v.id)}</td><td ${cell}>RAID ${enc(v.raid)}</td><td ${cell}>${enc(v.size)}</td>`
            + `<td ${cell}>${badge(v.status === 'OK', v.status)}</td></tr>`).join('');
        const drives = data.drives.map((d) => {
            const smart = d.smart_passed === null ? '-' : badge(d.smart_passed, d.smart_passed ? 'Passed' : 'Failed');
            const temp = d.temp === null ? '-' : `${enc(d.temp)} &deg;C`;
            const life = d.ssd_life_left === null ? '-' : `${enc(d.ssd_life_left)} %`;
            return `<tr><td ${cell}>${enc(d.bay)}</td><td ${cell}>${enc(d.volume)}</td><td ${cell}>${enc(d.role)}</td>`
                + `<td ${cell}>${enc(d.type)}</td><td ${cell}>${enc(d.size)}</td><td ${cell}>${enc(d.model)}</td>`
                + `<td ${cell}>${badge(d.status === 'OK', d.status)}</td><td ${cell}>${temp}</td>`
                + `<td ${cell}>${smart}</td><td ${cell}>${life}</td></tr>`;
        }).join('');
        const th = (names) => `<tr>${names.map((n) => `<th ${cell}>${n}</th>`).join('')}</tr>`;
        return head
            + `<table style="border-collapse:collapse;margin-bottom:8px">${th(['Volume', 'Level', 'Size', 'Status'])}${vols}</table>`
            + `<table style="border-collapse:collapse">${th(['Bay', 'Volume', 'Role', 'Type', 'Size', 'Model', 'Status', 'Temp', 'SMART', 'SSD life'])}${drives}</table>`;
    }

    function attach(summary) {
        if (summary.homelabStorage || !summary.rendered || !summary.pveSelNode) {
            return;
        }
        const nodename = summary.pveSelNode.data.node;
        const target = summary.down('#itemcontainer') || summary;
        const panel = Ext.create('Ext.panel.Panel', {
            title: gettext('Storage (Smart Array)'),
            itemId: 'homelabStorage',
            columnWidth: 1,
            bodyPadding: 8,
            html: '<i>Loading...</i>',
        });
        summary.homelabStorage = panel;
        target.insert(0, panel);

        const load = () => Proxmox.Utils.API2Request({
            url: `/nodes/${nodename}/config`,
            method: 'GET',
            success: (response) => {
                let html;
                try {
                    html = render(parseNotes(response.result.data.description));
                } catch (err) {
                    html = `<i>Could not read the Smart Array data: ${enc(err.message)}</i>`;
                }
                if (!panel.destroyed) {
                    panel.setHtml(html);
                }
            },
            failure: (response) => {
                if (!panel.destroyed) {
                    panel.setHtml(`<i>${enc(response.htmlStatus)}</i>`);
                }
            },
        });
        const task = Ext.TaskManager.start({ run: load, interval: REFRESH_MS });
        panel.on('destroy', () => Ext.TaskManager.stop(task));
    }

    Ext.onReady(() => {
        setInterval(() => Ext.ComponentQuery.query('pveNodeSummary').forEach(attach), SCAN_MS);
    });
})();
