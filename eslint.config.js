const globals = require('globals');
const react = require('eslint-plugin-react');
const reactHooks = require('eslint-plugin-react-hooks');
const testingLibrary = require('eslint-plugin-testing-library');
const importPlugin = require('eslint-plugin-import');
const identity = require('@18f/eslint-plugin-identity');

// Files/directories previously excluded via `.eslintignore`. In flat config these are expressed
// as a config object containing only `ignores`. The legacy `.eslintignore` used gitignore
// semantics where a bare `fixtures` matched any directory named `fixtures` at any depth, so the
// flat equivalent uses `**/fixtures/**`.
const ignores = [
  '**/fixtures/**',
  'node_modules/**',
  'public/**',
  'vendor/**',
  'coverage/**',
  'doc/**',
  'app/javascript/packages/analytics/digital-analytics-program*.js',
];

module.exports = [
  { ignores },

  // Base shared configuration from @18f/eslint-plugin-identity. This is an array of flat config
  // objects (base JS/JSX + TypeScript) that layer in React, TypeScript, Mocha, and Prettier support
  // based on installed peer dependencies.
  ...identity.configs.recommended,

  // Equivalent of the legacy `extends`:
  //   "plugin:react/recommended", "plugin:react-hooks/recommended", "plugin:react/jsx-runtime"
  // Scoped to the file globs the identity config applies to.
  {
    name: 'identity-idp/react',
    files: ['**/*.{js,jsx,ts,tsx,cjs,mjs}'],
    plugins: {
      react,
      'react-hooks': reactHooks,
    },
    rules: {
      ...react.configs.flat.recommended.rules,
      ...reactHooks.configs.recommended.rules,
      // plugin:react/jsx-runtime — not needed with the new JSX transform.
      'react/react-in-jsx-scope': 'off',
      'react/jsx-uses-react': 'off',
    },
  },

  // Project-wide settings, globals, and rule overrides (formerly the top-level keys of .eslintrc).
  {
    name: 'identity-idp/project',
    files: ['**/*.{js,jsx,ts,tsx,cjs,mjs}'],
    plugins: {
      import: importPlugin,
      'testing-library': testingLibrary,
    },
    languageOptions: {
      globals: {
        ...globals.browser,
        ...globals.commonjs,
        globalThis: true,
      },
    },
    settings: {
      'import/internal-regex': '^@18f/identity-',
    },
    rules: {
      // `no-unresolved` doesn't support package.json exports
      // See: https://github.com/import-js/eslint-plugin-import/issues/1810
      'import/no-unresolved': ['error', { ignore: ['intl-tel-input'] }],
      'no-restricted-syntax': [
        'error',
        {
          selector:
            "AssignmentExpression[left.property.name='href'][right.type=/(Template)?Literal/],NewExpression[callee.name=URL][arguments.0.type=/(Template)?Literal/]",
          message: 'Avoid hard-coded string URLs, since they will not include the current locale',
        },
      ],
      'react-hooks/exhaustive-deps': 'error',
    },
  },

  // Spec files: enable the testing-library rules and relax some rules.
  {
    name: 'identity-idp/specs',
    files: [
      '**/*.spec.{js,jsx,ts,tsx,cjs,mjs}',
      '**/*-spec.{js,jsx,ts,tsx,cjs,mjs}',
      '**/*_spec.{js,jsx,ts,tsx,cjs,mjs}',
      'spec/**/*.{js,jsx,ts,tsx,cjs,mjs}',
    ],
    plugins: {
      import: importPlugin,
      react,
      'testing-library': testingLibrary,
    },
    languageOptions: {
      globals: {
        expect: true,
      },
    },
    rules: {
      'react/jsx-props-no-spreading': 'off',
      'import/no-extraneous-dependencies': [
        'error',
        {
          devDependencies: true,
          packageDir: '.',
        },
      ],
      'no-restricted-syntax': 'off',
      'testing-library/await-async-events': 'error',
      'testing-library/await-async-queries': 'error',
      'testing-library/await-async-utils': 'error',
      'testing-library/no-await-sync-events': 'error',
      'testing-library/no-await-sync-queries': 'error',
      'testing-library/no-debugging-utils': 'error',
    },
  },

  {
    name: 'identity-idp/exhaustive-deps-exceptions',
    files: [
      'app/javascript/packages/address-search/components/full-address-search-input.tsx',
      'app/javascript/packages/components/hooks/use-focus-trap.ts',
      'app/javascript/packages/components/hooks/use-toggle-body-class-by-presence.ts',
      'app/javascript/packages/document-capture/components/acuant-camera.tsx',
      'app/javascript/packages/document-capture/components/acuant-capture-canvas.jsx',
      'app/javascript/packages/document-capture/components/acuant-capture.tsx',
      'app/javascript/packages/document-capture/components/acuant-selfie-camera.tsx',
      'app/javascript/packages/document-capture/components/callback-on-mount.jsx',
      'app/javascript/packages/document-capture/components/document-capture-warning.tsx',
      'app/javascript/packages/document-capture/components/document-capture.tsx',
      'app/javascript/packages/document-capture/components/file-image.jsx',
      'app/javascript/packages/document-capture/components/file-input.tsx',
      'app/javascript/packages/document-capture/components/in-person-location-full-address-entry-post-office-search-step.tsx',
      'app/javascript/packages/document-capture/components/in-person-location-post-office-search-step.tsx',
      'app/javascript/packages/document-capture/components/in-person-switch-back-step.tsx',
      'app/javascript/packages/document-capture/components/review-issues-step.tsx',
      'app/javascript/packages/document-capture/components/submission-interstitial.jsx',
      'app/javascript/packages/document-capture/context/acuant.tsx',
      'app/javascript/packages/document-capture/hooks/use-cookie.js',
      'app/javascript/packages/form-steps/form-steps.spec.tsx',
      'app/javascript/packages/form-steps/form-steps.tsx',
      'app/javascript/packages/form-steps/use-history-param.ts',
      'app/javascript/packages/react-hooks/use-did-update-effect.ts',
      'app/javascript/packages/react-hooks/use-immutable-callback.ts',
      'app/javascript/packages/react-hooks/use-object-memo.ts',
    ],
    rules: {
      'react-hooks/exhaustive-deps': 'off',
    },
  },

  {
    name: 'identity-idp/prop-types-exceptions',
    files: [
      'app/javascript/packages/address-search/components/in-person-locations.spec.tsx',
      'app/javascript/packages/components/spinner-dots.jsx',
      'app/javascript/packages/document-capture/components/acuant-capture.tsx',
      'app/javascript/packages/document-capture/components/acuant-selfie-capture-canvas.jsx',
      'app/javascript/packages/document-capture/components/document-side-acuant-capture.jsx',
      'app/javascript/packages/document-capture/components/file-image.jsx',
      'app/javascript/packages/document-capture/components/file-input.tsx',
      'app/javascript/packages/document-capture/components/in-person-location-full-address-entry-post-office-search-step.tsx',
      'app/javascript/packages/document-capture/components/in-person-location-post-office-search-step.tsx',
      'app/javascript/packages/document-capture/components/in-person-prepare-step.tsx',
      'app/javascript/packages/document-capture/components/submission-interstitial.jsx',
      'app/javascript/packages/document-capture/components/submission.jsx',
      'spec/javascript/packages/document-capture/context/failed-capture-attempts-spec.jsx',
      'spec/javascript/packages/document-capture/hooks/use-async-spec.jsx',
    ],
    rules: {
      'react/prop-types': 'off',
    },
  },

  {
    name: 'identity-idp/jsx-key-exceptions',
    files: [
      'app/javascript/packages/components/status-page.spec.tsx',
      'app/javascript/packages/document-capture/components/warning.tsx',
    ],
    rules: {
      'react/jsx-key': 'off',
    },
  },

  {
    name: 'identity-idp/display-name-exceptions',
    files: ['app/javascript/packages/document-capture/higher-order/with-props.jsx'],
    rules: {
      'react/display-name': 'off',
    },
  },

  {
    name: 'identity-idp/rules-of-hooks-exceptions',
    files: [
      'app/javascript/packages/form-steps/form-steps.spec.tsx',
      'spec/javascript/spec_helper.js',
    ],
    rules: {
      'react-hooks/rules-of-hooks': 'off',
    },
  },

  // The flat config file itself legitimately imports ESLint plugins (dev tooling), so exempt it
  // from the `import/no-extraneous-dependencies` devDependencies check. The legacy `.eslintrc` was
  // JSON and therefore never linted, so this preserves that effective behavior. Placed last so it
  // wins over earlier config objects.
  {
    name: 'identity-idp/eslint-config-file',
    files: ['eslint.config.js'],
    rules: {
      'import/no-extraneous-dependencies': 'off',
    },
  },
];
