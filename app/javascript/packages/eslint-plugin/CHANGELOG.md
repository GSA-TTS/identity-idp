## Unreleased

## v3.0.0

### Breaking changes

- **Flat config only.** The shareable configuration is now published exclusively in ESLint's [flat config](https://eslint.org/docs/latest/use/configure/configuration-files) format. The legacy `.eslintrc` format (`extends: ["plugin:@18f/eslint-plugin-identity/recommended"]`) is no longer supported. Consumers must migrate to `eslint.config.js` and spread the config array:
  ```js
  const identity = require('@18f/eslint-plugin-identity');
  module.exports = [...identity.configs.recommended];
  ```
- `configs.recommended` is now an **array** of flat config objects (previously a single eslintrc object). React/TypeScript/Mocha/Prettier support continues to be layered in automatically based on detected peer dependencies.
- Updated peer dependency to require ESLint >= 8.57 (the first version with flat config support in the ESLint 8 line). Supports ESLint 8.57, 9, and 10.
- `eslint-plugin-import` moved from a peer dependency to a direct dependency, since the config always references it directly as a plugin object (flat config requires importing plugins rather than naming them as strings).

### Backwards-compatible changes

- `globals` is now a direct dependency, used to supply the environment globals (`es2021`, `node`) that the legacy `env` key previously provided.

### Backwards-compatible changes (carried over from unreleased)

- Language ECMAVersion increased from `2018` to `"latest"`
- Disabled many stylistic rules which would be redundant with Prettier formatting. For stylistic enforcement, it's recommended to opt-in to the optional Prettier rule extension.
  - `array-bracket-spacing`
  - `arrow-parens`
  - `arrow-spacing`
  - `block-spacing`
  - `brace-style`
  - `comma-spacing`
  - `comma-style`
  - `computed-property-spacing`
  - `dot-location`
  - `func-call-spacing`
  - `function-call-argument-newline`
  - `generator-star-spacing`
  - `jsx-quotes`
  - `key-spacing`
  - `keyword-spacing`
  - `no-extra-semi`
  - `no-tabs`
  - `no-trailing-spaces`
  - `object-curly-spacing`
  - `padded-blocks`
  - `quote-props`
  - `rest-spread-spacing`
  - `semi`
  - `semi-spacing`
  - `semi-style`
  - `space-before-function-paren`
  - `space-in-parens`
  - `switch-colon-spacing`
  - `template-curly-spacing`
  - `template-tag-spacing`
  - `yield-star-spacing`
- TypeScript: More default ESLint rules have been substituted with TypeScript-enhanced versions:
  - `default-param-last`
  - `lines-between-class-members`
  - `no-array-constructor`
  - `no-dupe-class-members`
  - `no-empty-function`
  - `no-loop-func`
  - `no-loss-of-precision`
  - `no-redeclare`
  - `no-useless-constructor`
- The following rules are no longer enforced:
  - `lines-between-class-members`
  - `no-restricted-globals`
  - `no-restricted-properties`
- React: The following rules are no longer enforced:
  - `react/no-array-index-key`
  - `react/sort-comp` (use function components instead)
- React: The following rules have been reconfigured in a backwards-compatible manner.
  - `jsx-a11y/label-has-associated-control` now allows _either_ label for or nesting, previously requiring both.
- `prefer-const` is only enforced on destructuring assignment if all variables should be `const` ([`destructuring: 'all'` option](https://eslint.org/docs/latest/rules/prefer-const#destructuring)).

### Dependencies

- Remove dependency on `eslint-config-airbnb` and `eslint-config-airbnb-base`.

## v2.0.0 (2022-03-14)

### Breaking changes

- Updated peer dependencies to require ESLint >= 8 ([see migration guide](https://eslint.org/docs/8.0.0/user-guide/migrating-to-8.0.0)).
- Updated base Airbnb shared configurations, introducing newly-enforced rules (see [`airbnb` changelog](https://github.com/airbnb/javascript/blob/master/packages/eslint-config-airbnb/CHANGELOG.md), [`airbnb-base` changelog](https://github.com/airbnb/javascript/blob/master/packages/eslint-config-airbnb-base/CHANGELOG.md)).
- Removed Babel auto-configuration. As an alternative, consider [configuring ESLint to use modern syntax and/or JSX](https://eslint.org/docs/user-guide/configuring/language-options#specifying-parser-options), or use the new TypeScript configuration.
- Automatic opt-in behavior has changed and now requires you to install the requisite peer dependencies to your project. Refer to README.md for details.

### New features

- Added new TypeScript opt-in automatic configuration.

### Backwards-compatible changes

- `no-cond-assign` is now configured with the [`except-parens` option](https://eslint.org/docs/rules/no-cond-assign#except-parens).

## v1.0.0 (2021-09-03)

- Initial release
