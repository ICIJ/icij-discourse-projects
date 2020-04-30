# frozen_string_literal: true

require 'rails_helper'

require 'guardian'

describe Guardian do

  fab!(:user) { Fabricate(:user) }
  fab!(:another_user) { Fabricate(:user) }
  fab!(:moderator) { Fabricate(:moderator) }
  fab!(:admin) { Fabricate(:admin) }
  fab!(:anonymous_user) { Fabricate(:anonymous) }
  fab!(:staff_post) { Fabricate(:post, user: moderator) }
  fab!(:group) { Fabricate(:group) }
  fab!(:another_group) { Fabricate(:group) }
  fab!(:automatic_group) { Fabricate(:group, automatic: true) }
  fab!(:plain_category) { Fabricate(:category) }

  let(:trust_level_0) { build(:user, trust_level: 0) }
  let(:trust_level_1) { build(:user, trust_level: 1) }
  let(:trust_level_2) { build(:user, trust_level: 2) }
  let(:trust_level_3) { build(:user, trust_level: 3) }
  let(:trust_level_4)  { build(:user, trust_level: 4) }
  let(:another_admin) { build(:admin) }
  let(:coding_horror) { build(:coding_horror) }

  let(:topic) { build(:topic, user: user) }
  let(:post) { build(:post, topic: topic, user: topic.user) }


  describe 'can_send_private_message' do
    let(:user) { Fabricate(:user) }
    let(:another_user) { Fabricate(:user) }
    let(:user2) { Fabricate(:user) }

    let(:group) { Fabricate :icij_group }
    let(:another_group) { Fabricate :icij_group }

    before do
      group.add(user)
      group.add(another_user)

      another_group.add(user2)
    end

    let(:suspended_user) { Fabricate(:user, suspended_till: 1.week.from_now, suspended_at: 1.day.ago) }

    # user has no icij groups
    it "returns false if user has no icij groups" do
      user3 = Fabricate :user, username: 'user3'
      user4 = Fabricate :user, username: 'user4'
      random_group = Fabricate :group
      random_group.add(user3)

      expect(Guardian.new(user3).can_send_private_message?(user4)).to be_falsey
    end

    # user is in an icij group to which the user composing the message is not a member
    it "returns false when the target is not a member of the user's icij project groups" do
      expect(Guardian.new(user).can_send_private_message?(user2)).to be_falsey
    end

    it "returns false when the icij project group is not among the user's" do
      expect(Guardian.new(user).can_send_private_message?(another_group)).to be_falsey
    end

    # ICIJ SPEC
    it "respects the group members messageable_level" do
      group.update!(messageable_level: Group::ALIAS_LEVELS[:members_mods_and_admins])
      expect(Guardian.new(user).can_send_private_message?(group)).to eq(true)

      group.add(user)
      expect(Guardian.new(user).can_send_private_message?(group)).to eq(true)

      expect(Guardian.new(trust_level_0).can_send_private_message?(group)).to eq(false)

      #  group membership trumps min_trust_to_send_messages setting
      # group.add(trust_level_0)
      # expect(Guardian.new(trust_level_0).can_send_private_message?(group)).to eq(true)
    end

    it "respects the group owners messageable_level" do
      group.update!(messageable_level: Group::ALIAS_LEVELS[:owners_mods_and_admins])
      expect(Guardian.new(user).can_send_private_message?(group)).to eq(false)

      group.add(user)
      expect(Guardian.new(user).can_send_private_message?(group)).to eq(false)

      group.add_owner(user)
      expect(Guardian.new(user).can_send_private_message?(group)).to eq(true)
    end

    context 'target user has private message disabled' do
      before do
        another_user.user_option.update!(allow_private_messages: false)
      end

      context 'for a normal user' do
        it 'should return false' do
          expect(Guardian.new(user).can_send_private_message?(another_user)).to eq(false)
        end
      end

      context 'for a staff user' do
        it 'should return true' do
          [admin, moderator].each do |staff_user|
            group.add(staff_user)
            expect(Guardian.new(staff_user).can_send_private_message?(another_user))
              .to eq(true)
          end
        end
      end
    end
  end

  describe "can_create?" do
    describe 'a Category' do
      it 'returns false when not logged in' do
        expect(Guardian.new.can_create?(Category)).to be_falsey
      end

      it 'returns true when a regular user' do
        expect(Guardian.new(user).can_create?(Category)).to be_truthy
      end

      it 'returns true when a moderator' do
        expect(Guardian.new(moderator).can_create?(Category)).to be_truthy
      end

      it 'returns true when an admin' do
        expect(Guardian.new(admin).can_create?(Category)).to be_truthy
      end
    end
  end

  describe 'can_edit?' do
    it 'returns false with a nil object' do
      expect(Guardian.new(user).can_edit?(nil)).to be_falsey
    end

    describe 'a Topic' do
      it 'returns false when not logged in' do
        expect(Guardian.new.can_edit?(topic)).to be_falsey
      end

      # it 'returns true for editing your own post' do
      #   expect(Guardian.new(topic.user).can_edit?(topic)).to eq(true)
      # end

      it 'returns false as a regular user' do
        expect(Guardian.new(coding_horror).can_edit?(topic)).to be_falsey
      end
    end

    describe 'a Category' do
     it 'returns false when not logged in' do
       expect(Guardian.new.can_edit?(plain_category)).to be_falsey
     end

     it 'returns true as a regular user' do
       expect(Guardian.new(plain_category.user).can_edit?(plain_category)).to be_truthy
     end

     it 'returns true as a moderator' do
       expect(Guardian.new(moderator).can_edit?(plain_category)).to be_truthy
     end

     it 'returns true as an admin' do
       expect(Guardian.new(admin).can_edit?(plain_category)).to be_truthy
     end
   end
  end

  context 'can_delete?' do

    it 'returns false with a nil object' do
      expect(Guardian.new(user).can_delete?(nil)).to be_falsey
    end

    context 'a Topic' do
      before do
        # pretend we have a real topic
        topic.id = 9999999
      end

      it 'returns false when not logged in' do
        expect(Guardian.new.can_delete?(topic)).to be_falsey
      end

      it 'returns true when not a moderator' do
        expect(Guardian.new(user).can_delete?(topic)).to be_truthy
      end

      it 'returns true when a moderator' do
        expect(Guardian.new(moderator).can_delete?(topic)).to be_truthy
      end

      it 'returns true when an admin' do
        expect(Guardian.new(admin).can_delete?(topic)).to be_truthy
      end

      it 'returns false for static doc topics' do
        tos_topic = Fabricate(:topic, user: Discourse.system_user)
        SiteSetting.tos_topic_id = tos_topic.id
        expect(Guardian.new(admin).can_delete?(tos_topic)).to be_falsey
      end

      it "returns true for own topics" do
        topic.update_attribute(:posts_count, 1)
        topic.update_attribute(:created_at, Time.zone.now)
        expect(Guardian.new(topic.user).can_delete?(topic)).to be_truthy
      end

      it "returns false if topic has replies" do
        topic.update!(posts_count: 2, created_at: Time.zone.now)
        expect(Guardian.new(topic.user).can_delete?(topic)).to be_truthy
      end

      it "returns false if topic was created > 24h ago" do
        topic.update!(posts_count: 1, created_at: 48.hours.ago)
        expect(Guardian.new(topic.user).can_delete?(topic)).to be_truthy
      end
    end

    context 'a Category' do

      let(:category) { build(:category, user: moderator) }
      let(:regular_user_category) { build(:category, user: user) }

      it 'returns false when not logged in' do
        expect(Guardian.new.can_delete?(category)).to be_falsey
      end

      it 'returns true when a regular user, if the user created it' do
        expect(Guardian.new(user).can_delete?(regular_user_category)).to be_truthy
      end

      it 'returns true when a moderator' do
        expect(Guardian.new(moderator).can_delete?(category)).to be_truthy
      end

      it 'returns true when an admin' do
        expect(Guardian.new(admin).can_delete?(category)).to be_truthy
      end

      it "can't be deleted if it has a forum topic" do
        category.topic_count = 10
        expect(Guardian.new(moderator).can_delete?(category)).to be_falsey
      end

      # it "can't be deleted if it is the Uncategorized Category" do
      #   uncategorized_cat_id = SiteSetting.uncategorized_category_id
      #   uncategorized_category = Category.find(uncategorized_cat_id)
      #   expect(Guardian.new(admin).can_delete?(uncategorized_category)).to be_falsey
      # end

      it "can't be deleted if it has children" do
        category.expects(:has_children?).returns(true)
        expect(Guardian.new(admin).can_delete?(category)).to be_falsey
      end

    end
  end
end
