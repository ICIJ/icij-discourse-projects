# frozen_string_literal: true

require 'rails_helper'

describe Group do
  context "filtering out icij groups (projects) generated via xemx" do
    it "icij_projects scope returns groups with icij_group: true" do
      icij_group = Fabricate(:icij_group)
      other_icij_group = Fabricate(:icij_group, name: "other-icij-project")
      group = Fabricate(:group)
      expect(Group.icij_projects.count).to eq(2)
      expect(Group.icij_projects.pluck(:icij_group)).to eq([true, true])
    end
  end

  context "getting icij projects for a specific user using visible_icij_groups" do
    it "returns icij_projects for a given user" do
      icij_group = Fabricate(:icij_group)
      other_icij_group = Fabricate(:icij_group, name: "other-icij-project")

      user = Fabricate(:user)
      other_user = Fabricate(:user)

      icij_group.add(user)
      other_icij_group.add(user)

      icij_group.add(other_user)

      expect(Group.visible_icij_groups(user).count).to eq(2)
      expect(Group.visible_icij_groups(other_user).count).to eq(1)

      expect(icij_group.users.count).to eq(2)
      expect(other_icij_group.users.count).to eq(1)
    end

    it "returns an empty array for a nil user" do
      user = nil
      expect(Group.visible_icij_groups(user).count).to eq(0)
    end
  end

  context "icij project group activity tab" do
    it "shows only the posts for a given icij project group" do
      user = Fabricate(:user)

      icij_group = Fabricate(:icij_group)
      icij_group.add(user)

      another_icij_group = Fabricate(:icij_group)

      public_cat = Fabricate(:category) # public category
      public_post = Fabricate(:post, topic: Fabricate(:topic, category: public_cat))

      private_cat = Fabricate(:category)
      private_cat.set_permissions(icij_group.id => 1)
      private_cat.save

      another_private_cat = Fabricate(:category)
      another_private_cat.set_permissions(another_icij_group.id => 1)
      another_private_cat.save

      icij_group.update!(categories: [private_cat])
      another_icij_group.update!(categories: [another_private_cat])

      private_post = Fabricate(:post, topic: Fabricate(:topic, category: private_cat))
      icij_group.add(private_post.user)

      another_private_post = Fabricate(:post, topic: Fabricate(:topic, category: another_private_cat))

      icij_group_posts = icij_group.posts_for(Guardian.new(user))

      # should only include the posts for that specific icij project group
      expect(icij_group_posts.pluck(:id)).to include(private_post.id)
      # should not include public posts
      expect(icij_group_posts.pluck(:id)).to_not include(public_post.id)
      # should not include the posts of another icij project group
      expect(icij_group_posts.pluck(:id)).to_not include(another_private_post.id)
    end
  end
end
