require 'spec_helper'

describe "Checkout" do

  let!(:country) { create(:country, :states_required => true) }
  let!(:state) { create(:state, :country => country) }
  let!(:shipping_method) { create(:shipping_method) }
  let!(:stock_location) { create(:stock_location) }
  let!(:mug) { create(:product, :name => "RoR Mug") }
  let!(:payment_method) { create(:payment_method) }
  let!(:zone) { create(:zone) }

  context "visitor makes checkout as guest without registration" do
    before(:each) do
      stock_location.stock_items.update_all(count_on_hand: 1)
    end

    context "defaults to use billing address" do
      before do
        add_mug_to_cart
        Spree::Order.last.update_column(:email, "ryan@spreecommerce.com")
        click_button "Checkout"
      end

      it "should default checkbox to checked" do
        find('input#order_use_billing').should be_checked
      end

      it "should remain checked when used and visitor steps back to address step", :js => true do
        fill_in_address
        find('input#order_use_billing').should be_checked
      end
    end

    # Regression test for #1596
    context "full checkout" do
      before do
        mug.shipping_category = shipping_method.shipping_categories.first
        mug.save!
      end

      it "does not break the per-item shipping method calculator", :js => true do
        add_mug_to_cart
        click_button "Checkout"

        fill_in "order_email", :with => "ryan@spreecommerce.com"
        click_button "Continue"
        fill_in_address

        click_button "Save and Continue"
        page.should_not have_content("undefined method `promotion'")

        click_button "Save and Continue"
        page.should have_content(shipping_method.name)
      end

      # Regression test, no issue number
      it "does not create a closed adjustment for an order's shipment upon reaching the delivery step", :js => true do
        add_mug_to_cart
        click_button "Checkout"

        fill_in "order_email", :with => "ryan@spreecommerce.com"
        click_button "Continue"
        fill_in_address

        click_button "Save and Continue"
        Spree::Order.last.shipments.first.adjustment.state.should_not == "closed"
      end
    end
  end

  #regression test for #2694
  context "doesn't allow bad credit card numbers" do
    before(:each) do
      order = OrderWalkthrough.up_to(:delivery)
      order.stub :confirmation_required? => true
      order.stub(:available_payment_methods => [ create(:bogus_payment_method, :environment => 'test') ])

      user = create(:user)
      order.user = user
      order.update!

      Spree::CheckoutController.any_instance.stub(:current_order => order)
      Spree::CheckoutController.any_instance.stub(:try_spree_current_user => user)
      Spree::CheckoutController.any_instance.stub(:skip_state_validation? => true)
    end

    it "redirects to payment page" do
      visit spree.checkout_state_path(:delivery)
      click_button "Save and Continue"
      choose "Credit Card"
      fill_in "Card Number", :with => '123'
      fill_in "Card Code", :with => '123'
      click_button "Save and Continue"
      click_button "Place Order"
      page.should have_content("Payment could not be processed")
      click_button "Place Order"
      page.should have_content("Payment could not be processed")
    end
  end

  context "and likes to double click buttons" do
    before(:each) do
      user = create(:user)

      order = OrderWalkthrough.up_to(:delivery)
      order.stub :confirmation_required? => true

      order.reload
      order.user = user
      order.update!

      Spree::CheckoutController.any_instance.stub(:current_order => order)
      Spree::CheckoutController.any_instance.stub(:try_spree_current_user => user)
      Spree::CheckoutController.any_instance.stub(:skip_state_validation? => true)
    end

    it "prevents double clicking the payment button on checkout", :js => true do
      visit spree.checkout_state_path(:payment)

      # prevent form submit to verify button is disabled
      page.execute_script("$('#checkout_form_payment').submit(function(){return false;})")

      page.should_not have_selector('input.button[disabled]')
      click_button "Save and Continue"
      page.should have_selector('input.button[disabled]')
    end

    it "prevents double clicking the confirm button on checkout", :js => true do
      visit spree.checkout_state_path(:confirm)

      # prevent form submit to verify button is disabled
      page.execute_script("$('#checkout_form_confirm').submit(function(){return false;})")

      page.should_not have_selector('input.button[disabled]')
      click_button "Place Order"
      page.should have_selector('input.button[disabled]')
    end
  end

  context "when several payment methods are available" do
    let(:credit_cart_payment) {create(:bogus_payment_method, :environment => 'test') }
    let(:check_payment) {create(:payment_method, :environment => 'test') }

    after do
      Capybara.ignore_hidden_elements = true
    end

    before do
      Capybara.ignore_hidden_elements = false
      order = OrderWalkthrough.up_to(:delivery)
      order.stub(:available_payment_methods => [check_payment,credit_cart_payment])
      order.user = create(:user)
      order.update!

      Spree::CheckoutController.any_instance.stub(current_order: order)
      Spree::CheckoutController.any_instance.stub(try_spree_current_user: order.user)

      visit spree.checkout_state_path(:payment)
    end

    it "the first payment method should be selected", :js => true do
      payment_method_css = "#order_payments_attributes__payment_method_id_"
      find("#{payment_method_css}#{check_payment.id}").should be_checked
      find("#{payment_method_css}#{credit_cart_payment.id}").should_not be_checked
    end

    it "the fields for the other payment methods should be hidden", :js => true do
      payment_method_css = "#payment_method_"
      find("#{payment_method_css}#{check_payment.id}").should be_visible
      find("#{payment_method_css}#{credit_cart_payment.id}").should_not be_visible
    end
  end

  # regression for #2921
  context "goes back from payment to add another item", js: true do
    let!(:bag) { create(:product, :name => "RoR Bag") }

    it "transit nicely through checkout steps again" do
      add_mug_to_cart
      click_on "Checkout"
      fill_in "order_email", :with => "ryan@spreecommerce.com"
      click_button "Continue"
      fill_in_address
      click_on "Save and Continue"
      click_on "Save and Continue"
      expect(current_path).to eql(spree.checkout_state_path("payment"))

      visit spree.root_path
      click_link bag.name
      click_button "add-to-cart-button"

      click_on "Checkout"
      click_on "Save and Continue"
      click_on "Save and Continue"
      click_on "Save and Continue"

      expect(current_path).to eql(spree.order_path(Spree::Order.last))
    end
  end

  def fill_in_address
    address = "order_bill_address_attributes"
    fill_in "#{address}_firstname", :with => "Ryan"
    fill_in "#{address}_lastname", :with => "Bigg"
    fill_in "#{address}_address1", :with => "143 Swan Street"
    fill_in "#{address}_city", :with => "Richmond"
    select "United States of America", from: "#{address}_country_id", :match => :first
    select "Alabama", from: "#{address}_state_id", :match => :first
    fill_in "#{address}_zipcode", :with => "12345"
    fill_in "#{address}_phone", :with => "(555) 5555-555"
  end

  def add_mug_to_cart
    visit spree.root_path
    click_link mug.name
    click_button "add-to-cart-button"
  end
end
