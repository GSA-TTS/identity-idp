require 'rails_helper'

# This spec guards against a ViewComponent (or Lookbook) upgrade silently
# breaking component previews at `/components`.
#
# Background on the failure mode we are guarding against:
#
# ViewComponent's config is an ActiveSupport::OrderedOptions, which silently
# accepts assignment to *any* key. In the 3.x -> 4.x upgrade the top-level
# options (`preview_paths`, `preview_controller`, `show_previews`,
# `default_preview_layout`) were moved under a `previews` namespace. Because
# assigning to a removed key does not raise, `config/application.rb` kept
# writing to dead keys, the real `previews.paths` stayed at its (nonexistent)
# default, and Lookbook rendered zero components.
#
# The important detail: ViewComponent loads previews by globbing
# `ViewComponent::Base.previews.paths` (see
# `ViewComponent::Preview.__vc_load_previews`). That is the value that actually
# matters -- not the raw `config.view_component.*` we assign. This spec asserts
# against `ViewComponent::Base.previews` and against actually loading the
# previews off disk through the same code path Lookbook uses, so a future
# rename that leaves our assignments writing to dead keys will fail here.
RSpec.describe 'component previews', type: :request do
  before do
    unless IdentityConfig.store.component_previews_enabled
      skip 'component previews are not enabled in this environment'
    end
  end

  let(:expected_preview_path) { Rails.root.join('spec', 'components', 'previews').to_s }

  # The config that ViewComponent + Lookbook actually read at runtime, resolved
  # through ViewComponent::Base rather than the raw assignment target.
  let(:effective_previews_config) { ViewComponent::Base.previews }

  it 'enables previews' do
    expect(effective_previews_config.enabled).to eq(true)
  end

  it 'resolves previews.paths to our spec/components/previews directory' do
    expect(effective_previews_config.paths.map(&:to_s)).to include(expected_preview_path)
  end

  it 'uses our custom preview controller' do
    expect(effective_previews_config.controller).to eq('ComponentPreviewController')
  end

  it 'uses our custom preview layout' do
    expect(effective_previews_config.default_layout).to eq('component_preview')
  end

  it 'loads the on-disk preview classes through ViewComponent\'s own loader' do
    on_disk_preview_files = Dir[File.join(expected_preview_path, '**', '*preview.rb')]
    expect(on_disk_preview_files).not_to be_empty

    # Exercise the exact code path Lookbook/ViewComponent use to discover
    # previews. If previews.paths is misconfigured this returns nothing, even
    # though the preview classes may already be autoloaded elsewhere.
    loaded_source_files = ViewComponent::Preview.all.filter_map do |preview|
      example = preview.instance_methods(false).first
      next unless example

      preview.instance_method(example).source_location&.first
    end

    previews_from_our_path = loaded_source_files.select do |path|
      path.start_with?(expected_preview_path)
    end

    expect(previews_from_our_path).not_to be_empty,
                                          'ViewComponent did not discover any previews under ' \
                                          "#{expected_preview_path}. This usually means " \
                                          'config.view_component.previews.paths is not wired ' \
                                          'up correctly (e.g. a ViewComponent upgrade renamed ' \
                                          'the config keys we set in config/application.rb).'
  end

  it 'exposes previews through Lookbook, which is what renders the navigation' do
    # Lookbook builds its component navigation from `Lookbook.previews`. This is
    # the most direct assertion of "components show up in Lookbook": if the
    # preview path config is broken, this collection is empty even when the
    # preview classes are otherwise autoloadable.
    lookbook_previews = Lookbook.previews

    expect(lookbook_previews).not_to be_empty,
                                     'Lookbook discovered no previews. Components will not show ' \
                                     'up at /components. This usually means a ViewComponent or ' \
                                     'Lookbook upgrade changed the config keys we set in ' \
                                     'config/application.rb (e.g. previews.paths).'

    on_disk_preview_names = Dir[File.join(expected_preview_path, '*_preview.rb')].map do |file|
      File.basename(file, '_preview.rb')
    end
    lookbook_preview_names = lookbook_previews.map do |preview|
      # Lookbook preview entities expose the underscored name without suffix.
      preview.respond_to?(:preview_class) ? preview.preview_class.name : preview.to_s
    end.join(' ').underscore

    # Every on-disk preview should be represented in Lookbook's collection.
    on_disk_preview_names.each do |name|
      expect(lookbook_preview_names).to include(name.sub(/_preview\z/, ''))
    end
  end

  it 'serves the Lookbook previews index with our components' do
    get '/components'

    expect(response).to have_http_status(:ok)
    # A stable, human-named component that has a preview on disk. If preview
    # discovery is broken, Lookbook renders an empty navigation and this string
    # is absent.
    expect(response.body).to include('Accordion')
  end
end
