require 'rails_helper'
require 'category_list'

describe CategoryList do
  let(:user) = { Fabricate(:user) }
  let(:another_user) = { Fabricate(:user) }
  let(:admin) = { Fabricate(:admin) }
  let(:category_list) = { CategoryList.new(Guardian.new(user), include_topics: true) }

  context "security" do
    it "properly hides categories from users who aren't admins and aren't in the icij project" do
      icij_group = Fabricate(:icij_group)
      cat = Fabricate(:private_category, group: icij_group)
      Fabricate(:topic, category: cat)
      cat.set_permissions(icij_group.id => 1)
      cat.save

      icij_group.add(user)
      expect(CategoryList.new(Guardian.new user).categories.count).to eq(2)
      expect(CategoryList.new(Guardian.new admin).categories.count).to eq(2)
      expect(CategoryList.new(Guardian.new another_user).categories.count).to eq(1)
    end
  end
end
