require 'rails_helper'

RSpec.describe FormTabComponent, type: :component do
  include SimpleForm::ActionViewExtensions::FormHelper

  let(:view_context) { vc_test_controller.view_context }
  let(:form_object) { User.new }
  let(:form_builder) do
    SimpleForm::FormBuilder.new(form_object.model_name.param_key, form_object, view_context, {})
  end

  describe 'render' do
    let(:tab_a) { 'Item-A' }
    let(:tab_b) { 'Item-B' }
    let(:render_component) do
      render_inline described_class.new(form: form_builder) do |component|
        component.with_tab(label: 'Item-A') do
          '<div>Item-A Content</div>'.html_safe
        end

        component.with_tab(label: 'Item-B') do
          '<div>Item-B Content</div>'.html_safe
        end
      end
    end

    before do
      render_component
    end

    context 'initial load' do
      it 'renders the component with tab content' do
        expect(page).to have_css('div#form-tab-component')
        expect(page).to have_button('Item-A')
        expect(page).to have_button('Item-B', class: 'usa-button--outline')
        expect(page).to have_css('div', text: 'Item-A Content', visible: true)
        expect(page).to have_css('div', text: 'Item-B Content', visible: false)
      end
    end
  end
end
