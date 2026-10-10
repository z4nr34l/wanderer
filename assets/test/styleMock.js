// CSS module class names come back as their own key, so `classes.Foo` is "Foo" in tests.
module.exports = new Proxy({}, { get: (_target, key) => (key === '__esModule' ? false : key) });
