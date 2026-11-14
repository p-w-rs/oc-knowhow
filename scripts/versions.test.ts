import { test } from "node:test"
import assert from "node:assert/strict"
import { compareVersions, newestLike, parsePin } from "./versions.mjs"

test("pins are parsed from codeload URLs and compared with the newest matching upstream tag", () => {
  assert.deepEqual(parsePin("https://codeload.github.com/libsdl-org/SDL/tar.gz/refs/tags/release-3.4.20"), { repo: "libsdl-org/SDL", host: "github.com", kind: "tag", ref: "release-3.4.20" })
  assert.deepEqual(parsePin("https://codeload.github.com/ros2/rmw_zenoh/tar.gz/refs/heads/lyrical"), { repo: "ros2/rmw_zenoh", host: "github.com", kind: "branch", ref: "lyrical" })
  assert.equal(parsePin("https://codeload.github.com/floooh/sokol/tar.gz/93aa187b5d38")!.kind, "commit")
  assert.deepEqual(parsePin("https://gitlab.com/libeigen/eigen/-/archive/5.0.1/eigen-5.0.1.tar.gz"), { repo: "libeigen/eigen", host: "gitlab.com", kind: "tag", ref: "5.0.1" })
  assert.ok(compareVersions("release-3.4.20", "release-3.4.9") > 0)
  assert.ok(compareVersions("dev-2026-11a", "dev-2026-11") > 0)
  assert.ok(compareVersions("dev-2026-12", "dev-2026-11a") > 0)
  // Same family only: "v0.13.0" must not beat "dev-2026-11a"; release candidates are ignored.
  assert.equal(newestLike("dev-2026-11a", ["v0.13.0", "dev-2026-10", "dev-2026-11", "dev-2026-11a"]), "dev-2026-11a")
  assert.equal(newestLike("release-3.4.20", ["release-3.4.20", "release-3.5.0-rc1", "release-3.4.22", "prerelease-3.5.1"]), "release-3.4.22")
  assert.equal(newestLike("1.10.2", ["1.10.2", "1.11.0", "1.11.0-rc.1", "1.11.0+6-g06de48f", "v0.5"]), "1.11.0")
  assert.equal(newestLike("1.10.2", ["1.10.2", "1.10.2+6-g06de48f"]), "1.10.2")
  assert.equal(newestLike("v25.12.19", ["v25.12.19", "v25.12.19-2026-02-06-03fffb2"]), "v25.12.19")
  assert.equal(newestLike("apache-arrow-26.0.1", ["apache-arrow-26.0.1", "apache-arrow-27.0.0.dev"]), "apache-arrow-26.0.1")
  assert.equal(newestLike("4.3.0", ["4.3.0", "4.3a2"]), "4.3.0")
  assert.equal(newestLike("v1.5.7", ["v1.5.7", "v1.5.7-kernel"]), "v1.5.7")
  assert.equal(newestLike("v6.1", ["v6.1", "v6.1.1", "v6.2-dev"]), "v6.1.1")
  assert.equal(newestLike("dev-2026-11a", ["dev-2026-11a", "dev-2026-12"]), "dev-2026-12")
  assert.equal(newestLike("releases/python/mcap/v1.6.0", ["releases/python/mcap/v1.6.0", "releases/python/mcap/v1.7.0", "releases/cpp/v3.0.0"]), "releases/python/mcap/v1.7.0")
})
