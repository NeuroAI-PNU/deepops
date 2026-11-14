#!/usr/bin/env python3
"""xcc-redfish-probe - BMC hardware health -> node_exporter textfile (runs on ldap).

Why (2026-11-13): neuroai6's two NVMe drives sit behind a RAID 940-16i, where the OS cannot
run smartctl on them, and the XClarity Controller (BMC) is the only thing that sees fans,
PSUs, the RAID virtual disk and per-drive failure prediction. Its Redfish API reports all of
it with one Status.Health per component, so one probe covers RAID + hardware alerts.

Config: /etc/xcc-probe/<node>.conf (root 0600), one per BMC:
    bmc=192.168.0.107
    user=<read-only XCC account>
    password=<...>
Output: /run/prometheus/xcc_<node>.prom
    xcc_probe_success{node}            1 if the BMC answered
    xcc_probe_timestamp{node}          unix time of the last attempt
    xcc_health{node,kind,name}         0 OK, 1 Warning, 2 Critical  (kind: system, controller,
                                       volume, drive, fan, temperature, psu; absent parts skipped)
    xcc_drive_failure_predicted{node,name}   1 if the drive predicts failure
    xcc_drive_life_left_percent{node,name}   SSD endurance left, when the BMC reports it
"""
import base64, glob, json, os, ssl, sys, time, urllib.request

HEALTH = {"OK": 0, "Warning": 1, "Critical": 2}
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE        # XCC ships a self-signed cert; lab LAN only


def lbl(**kw):
    return "{" + ",".join('%s="%s"' % (k, str(v).replace("\\", "\\\\").replace('"', '\\"'))
                          for k, v in kw.items()) + "}"


class Bmc:
    def __init__(self, host, user, pw):
        self.base = "https://%s" % host
        self.auth = "Basic " + base64.b64encode(("%s:%s" % (user, pw)).encode()).decode()

    def get(self, path):
        req = urllib.request.Request(self.base + path, headers={"Authorization": self.auth})
        with urllib.request.urlopen(req, timeout=20, context=CTX) as r:
            return json.load(r)

    def members(self, path):
        # A collection that cannot be read (403 PasswordChangeRequired, 401, timeout) must fail the
        # whole probe; returning [] here reported success with zero components (seen 2026-11-14).
        return [self.get(m["@odata.id"]) for m in self.get(path).get("Members", [])]


def health(obj):
    st = obj.get("Status") or {}
    if st.get("State") in ("Absent", "Disabled", "UnavailableOffline"):
        return None
    return HEALTH.get(st.get("Health"))


def probe(node, cfg):
    b = Bmc(cfg["bmc"], cfg["user"], cfg["password"])
    out = []

    def add(kind, name, obj):
        h = health(obj)
        if h is not None:
            out.append("xcc_health%s %d" % (lbl(node=node, kind=kind, name=name), h))

    for sysobj in b.members("/redfish/v1/Systems"):
        add("system", sysobj.get("Id", "system"), sysobj)
        storage_link = (sysobj.get("Storage") or {}).get("@odata.id")
        if not storage_link:
            continue
        for st in b.members(storage_link):
            for c in st.get("StorageControllers", []):
                add("controller", c.get("Name") or st.get("Id"), c)
            add("controller", st.get("Name") or st.get("Id"), st)
            vols = (st.get("Volumes") or {}).get("@odata.id")
            for v in b.members(vols) if vols else []:
                add("volume", "%s %s" % (v.get("Name") or v.get("Id"), v.get("RAIDType", "")), v)
            for dref in st.get("Drives", []):
                try:
                    d = b.get(dref["@odata.id"])
                except Exception:
                    continue
                name = "%s %s" % (d.get("Name") or d.get("Id"), d.get("SerialNumber", ""))
                add("drive", name, d)
                if "FailurePredicted" in d and health(d) is not None:
                    out.append("xcc_drive_failure_predicted%s %d"
                               % (lbl(node=node, name=name), 1 if d["FailurePredicted"] else 0))
                life = d.get("PredictedMediaLifeLeftPercent")
                if isinstance(life, (int, float)):
                    out.append("xcc_drive_life_left_percent%s %g" % (lbl(node=node, name=name), life))

    for ch in b.members("/redfish/v1/Chassis"):
        th = (ch.get("Thermal") or {}).get("@odata.id")
        if th:
            t = b.get(th)
            for f in t.get("Fans", []):
                add("fan", f.get("Name") or f.get("MemberId"), f)
            for s in t.get("Temperatures", []):
                add("temperature", s.get("Name") or s.get("MemberId"), s)
        pw = (ch.get("Power") or {}).get("@odata.id")
        if pw:
            for p in b.get(pw).get("PowerSupplies", []):
                add("psu", p.get("Name") or p.get("MemberId"), p)
    return out


def main():
    os.makedirs("/run/prometheus", exist_ok=True)
    rc = 0
    for conf in sorted(glob.glob("/etc/xcc-probe/*.conf")):
        node = os.path.basename(conf)[:-5]
        cfg = dict(l.strip().split("=", 1) for l in open(conf) if "=" in l and not l.startswith("#"))
        lines = ["# HELP xcc_health BMC Redfish Status.Health (0 OK, 1 Warning, 2 Critical).",
                 "# TYPE xcc_health gauge"]
        try:
            lines += probe(node, cfg)
            ok = 1
        except Exception as e:
            print("%s: %s" % (node, e), file=sys.stderr)
            ok, rc = 0, 1
        if ok and not any(l.startswith("xcc_health{") for l in lines):
            print("%s: BMC answered but reported no components" % node, file=sys.stderr)
            ok, rc = 0, 1
        lines.append("xcc_probe_success%s %d" % (lbl(node=node), ok))
        lines.append("xcc_probe_timestamp%s %d" % (lbl(node=node), int(time.time())))
        path = "/run/prometheus/xcc_%s.prom" % node
        with open(path + ".tmp", "w") as f:
            f.write("\n".join(lines) + "\n")
        os.replace(path + ".tmp", path)
    return rc


if __name__ == "__main__":
    sys.exit(main())
