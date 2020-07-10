# frozen_string_literal: true

require 'rails_helper'

describe User do
  describe 'scope members_visible_icij_groups' do
    context 'user is nil' do
      it "returns an empty array" do
        user = nil

        expect(User.members_visible_icij_groups(user)).to eq([])
      end
    end

    context 'user is not a member of any projects' do
      it 'returns an empty array' do
        user = Fabricate(:user)

        icij_group = Fabricate(:icij_group)

        expect(User.members_visible_icij_groups(user)).to eq([])
      end
    end

    context 'user is the only project member' do
      it "returns the user's id alone in an array" do
        user = Fabricate(:user)
        site = Site.new(Guardian.new(user))

        icij_group = Fabricate(:icij_group)
        icij_group.add(user)

        expect(User.members_visible_icij_groups(user).include?(user)).to eq(true)
      end

      it "does not return users with negative ids (programmatic users)" do
        user = Fabricate(:user)
        site = Site.new(Guardian.new(user))

        icij_group = Fabricate(:icij_group)
        icij_group.add(user)

        expect((User.members_visible_icij_groups(user).pluck(:id)).all?(&:positive?)).to eq(true)
      end
    end

    context 'multiple project members' do
      it "returns the ids in an array" do
        user = Fabricate(:user)
        another_user = Fabricate(:user)
        site = Site.new(Guardian.new(user))

        icij_group = Fabricate(:icij_group)
        icij_group.add(user)
        icij_group.add(another_user)

        expect(User.members_visible_icij_groups(user).pluck(:id).include?(user.id) && User.members_visible_icij_groups(user).pluck(:id).include?(another_user.id)).to eq(true)
      end

      it "does not return users with negative ids (programmatic users)" do
        user = Fabricate(:user)
        another_user = Fabricate(:user)
        site = Site.new(Guardian.new(user))

        icij_group = Fabricate(:icij_group)
        icij_group.add(user)
        icij_group.add(another_user)

        expect((User.members_visible_icij_groups(user).pluck(:id)).all?(&:positive?)).to eq(true)
      end
    end
  end
end
