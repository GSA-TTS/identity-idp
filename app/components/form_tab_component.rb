# frozen_string_literal: true

class FormTabComponent < BaseComponent
  renders_many :tabs, ->(label:, &content_block) do
    TabItem.new(label:, content_block:)
  end

  def initialize(form:)
    @form = form
  end

  def before_render
    super
    tabs.first.active = true
  end

  class TabItem < BaseComponent
    attr_reader :label, :id
    attr_accessor :active

    def initialize(label:, content_block:)
      @label = label
      @content_block = content_block
      @active = false
      @id = SecureRandom.hex(8)
    end

    def button_id
      "button-#{id}"
    end

    def panel_id
      "panel-#{id}"
    end

    def call
      @content_block.call
    end
  end
end
