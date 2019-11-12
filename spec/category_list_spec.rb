require 'rails_helper'
require 'category_list'

describe CategoryList do
  let(:user) { Fabricate(:user) }
  let(:another_user) { Fabricate(:user) }
  let(:admin) { Fabricate(:admin) }

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

    it "properly hides topics from users who aren't admins and aren't in the icij project" do
      public_cat = Fabricate(:category) # public category
      Fabricate(:topic, category: public_cat)

      icij_group = Fabricate(:icij_group)
      private_cat = Fabricate(:category)
      Fabricate(:topic, category: private_cat)
      private_cat.set_permissions(icij_group.id => 1)
      private_cat.save

      icij_group.add(user)

      secret_subcat = Fabricate(:category, parent_category_id: private_cat.id) # private subcategory
      Fabricate(:topic, category: secret_subcat)
      secret_subcat.set_permissions(icij_group.id => 1)
      secret_subcat.save

      CategoryFeaturedTopic.feature_topics

      expect(CategoryList.new(Guardian.new(admin), include_topics: true).categories.find { |x| x.name == public_cat.name }.displayable_topics.count).to eq(1)
      expect(CategoryList.new(Guardian.new(admin), include_topics: true).categories.find { |x| x.name == private_cat.name }.displayable_topics.count).to eq(2)

      expect(CategoryList.new(Guardian.new(user), include_topics: true).categories.find { |x| x.name == public_cat.name }.displayable_topics.count).to eq(1)
      expect(CategoryList.new(Guardian.new(user), include_topics: true).categories.find { |x| x.name == private_cat.name }.displayable_topics.count).to eq(2)

      expect(CategoryList.new(Guardian.new(another_user), include_topics: true).categories.find { |x| x.name == public_cat.name }.displayable_topics.count).to eq(1)
      expect(CategoryList.new(Guardian.new(another_user), include_topics: true).categories.find { |x| x.name == private_cat.name }.nil?).to eq(true)
    end
  end
end
