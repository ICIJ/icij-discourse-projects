# frozen_string_literal: true

require 'rails_helper'

describe GroupsController do
  let(:user) { Fabricate(:user) }
  let(:icij_group) { Fabricate(:icij_group, users: [user]) }
  let(:moderator_group_id) { Group::AUTO_GROUPS[:moderators] }
  let(:admin) { Fabricate(:admin) }
  let(:moderator) { Fabricate(:moderator) }

  describe '#index' do
    let(:another_icij_group) do
      Fabricate(:icij_group, name: '0000', visibility_level: Group.visibility_levels[:members])
    end

    it 'should return the right response' do
      sign_in(user)

      icij_group
      another_icij_group
      get "/groups.json"

      expect(response.status).to eq(200)

      response_body = JSON.parse(response.body)

      group_ids = response_body["groups"].map { |g| g["id"] }

      expect(group_ids).to include(icij_group.id)
      expect(group_ids).to_not include(another_icij_group.id)
      expect(response_body["load_more_groups"]).to eq("/groups?page=1")
      expect(response_body["total_rows_groups"]).to eq(1)
    end

    context 'viewing groups of another user' do
      describe 'when an invalid username is given' do
        it 'should return 404 if an unknown username is given' do
          icij_group
          get "/groups.json", params: { username: 'asdasd' }

          expect(response.status).to eq(404)
        end
      end

      it 'should return the right response' do
        user2 = Fabricate(:user)
        icij_group.add(user2)
        sign_in(user2)

        get "/groups.json", params: { username: user.username }

        expect(response.status).to eq(200)

        response_body = JSON.parse(response.body)

        group_ids = response_body["groups"].map { |g| g["id"] }

        expect(group_ids).to contain_exactly(icij_group.id)
      end
    end
  end

  describe '#show' do
    it "ensures the group can be seen" do
      sign_in(Fabricate(:user))
      icij_group.update!(visibility_level: Group.visibility_levels[:owners])

      get "/g/#{icij_group.name}.json"

      expect(response.status).to eq(403)
    end

    it "returns the right response" do
      sign_in(user)
      get "/g/#{icij_group.name}.json"

      expect(response.status).to eq(200)

      response_body = JSON.parse(response.body)

      expect(response_body['group']['id']).to eq(icij_group.id)
      expect(response_body['extras']["visible_group_names"]).to eq([icij_group.name])
    end

    context 'as an admin' do
      it "returns the right response" do
        sign_in(Fabricate(:admin))
        get "/g/#{icij_group.name}.json"

        expect(response.status).to eq(200)

        response_body = JSON.parse(response.body)

        expect(response_body['group']['id']).to eq(icij_group.id)

        groups = Group::AUTO_GROUPS.keys
        groups.delete(:everyone)
        groups.push(icij_group.name)

        expect(response_body['extras']["visible_group_names"])
          .to contain_exactly(*groups.map(&:to_s))
      end
    end
  end

  describe "#posts" do
    it "ensures the group can be seen" do
      sign_in(Fabricate(:user))
      icij_group.update!(visibility_level: Group.visibility_levels[:owners])

      get "/g/#{icij_group.name}/posts.json"

      expect(response.status).to eq(403)
    end

    it "calls `posts_for` and responds with JSON" do
      sign_in(user)

      private_cat = Fabricate(:category)
      private_cat.set_permissions(icij_group.id => 1)
      private_cat.save

      icij_group.update!(categories: [private_cat])

      post =  Fabricate(:post, user: user, topic: Fabricate(:topic, category: private_cat, user: user)
)

      get "/g/#{icij_group.name}/posts.json"

      expect(response.status).to eq(200)

      expect(JSON.parse(response.body).first["id"]).to eq(post.id)
    end
  end

  describe "#members" do
    it "returns correct error code with invalid params" do
      sign_in(Fabricate(:user))

      get "/g/#{icij_group.name}/members.json?limit=-1"
      expect(response.status).to eq(400)

      get "/g/#{icij_group.name}/members.json?offset=-1"
      expect(response.status).to eq(400)
    end

    it "ensures the group can be seen" do
      sign_in(Fabricate(:user))
      icij_group.update!(visibility_level: Group.visibility_levels[:owners])

      get "/g/#{icij_group.name}/members.json"

      expect(response.status).to eq(403)
    end
  end

  describe '#update' do
    let(:group) do
      Fabricate(:icij_group,
        name: 'test',
        users: [user],
        public_admission: false,
        public_exit: false
      )
    end

    context "when user is group owner" do
      before do
        group.add_owner(user)
        sign_in(user)
      end

      it "should be able update the group" do
        group.update!(
          allow_membership_requests: false,
          visibility_level: 2,
          mentionable_level: 2,
          messageable_level: 2,
          default_notification_level: 0,
          grant_trust_level: 0,
          automatic_membership_retroactive: false
        )

        expect do
          put "/groups/#{group.id}.json", params: {
            group: {
              mentionable_level: 1,
              messageable_level: 1,
              visibility_level: 1,
              automatic_membership_email_domains: 'test.org',
              automatic_membership_retroactive: true,
              title: 'haha',
              primary_group: true,
              grant_trust_level: 1,
              incoming_email: 'test@mail.org',
              flair_bg_color: 'FFF',
              flair_color: 'BBB',
              flair_url: 'fa-adjust',
              bio_raw: 'testing',
              full_name: 'awesome team',
              public_admission: true,
              public_exit: true,
              allow_membership_requests: true,
              membership_request_template: 'testing',
              default_notification_level: 1,
              name: 'testing'
            }
          }
        end.to change { GroupHistory.count }.by(13)

        expect(response.status).to eq(200)

        group.reload

        expect(group.flair_bg_color).to eq('FFF')
        expect(group.flair_color).to eq('BBB')
        expect(group.flair_url).to eq('fa-adjust')
        expect(group.bio_raw).to eq('testing')
        expect(group.full_name).to eq('awesome team')
        expect(group.public_admission).to eq(true)
        expect(group.public_exit).to eq(true)
        expect(group.allow_membership_requests).to eq(true)
        expect(group.membership_request_template).to eq('testing')
        expect(group.name).to eq('test')
        expect(group.visibility_level).to eq(2)
        expect(group.mentionable_level).to eq(1)
        expect(group.messageable_level).to eq(1)
        expect(group.default_notification_level).to eq(1)
        expect(group.automatic_membership_email_domains).to eq(nil)
        expect(group.automatic_membership_retroactive).to eq(false)
        expect(group.title).to eq('haha')
        expect(group.primary_group).to eq(false)
        expect(group.incoming_email).to eq(nil)
        expect(group.grant_trust_level).to eq(0)
      end

      it 'should not be allowed to update automatic groups' do
        group = Group.find(Group::AUTO_GROUPS[:admins])

        put "/g/#{group.id}.json", params: {
          group: {
            messageable_level: 1
          }
        }

        expect(response.status).to eq(403)
      end
    end

    context "when user is group admin" do
      before do
        user.update_attributes!(admin: true)
        sign_in(user)
      end

      it 'should be able to update the group' do
        group.update!(
          visibility_level: 2,
          automatic_membership_retroactive: false,
          grant_trust_level: 0
        )

        put "/groups/#{group.id}.json", params: {
          group: {
            flair_color: 'BBB',
            name: 'testing',
            incoming_email: 'test@mail.org',
            primary_group: true,
            automatic_membership_email_domains: 'test.org',
            automatic_membership_retroactive: true,
            grant_trust_level: 2,
            visibility_level: 1
          }
        }

        expect(response.status).to eq(200)

        group.reload
        expect(group.flair_color).to eq('BBB')
        expect(group.name).to eq('testing')
        expect(group.incoming_email).to eq("test@mail.org")
        expect(group.primary_group).to eq(true)
        expect(group.visibility_level).to eq(1)
        expect(group.automatic_membership_email_domains).to eq('test.org')
        expect(group.automatic_membership_retroactive).to eq(true)
        expect(group.grant_trust_level).to eq(2)

        expect(Jobs::AutomaticGroupMembership.jobs.first["args"].first["group_id"])
          .to eq(group.id)
      end

      it "should be able to update an automatic group" do
        group = Group.find(Group::AUTO_GROUPS[:admins])

        group.update!(
          visibility_level: 2,
          mentionable_level: 2,
          messageable_level: 2,
          default_notification_level: 2
        )

        put "/groups/#{group.id}.json", params: {
          group: {
            flair_color: 'BBB',
            name: 'testing',
            visibility_level: 1,
            mentionable_level: 1,
            messageable_level: 1,
            default_notification_level: 1
          }
        }

        expect(response.status).to eq(200)

        group.reload
        expect(group.flair_color).to eq(nil)
        expect(group.name).to eq('admins')
        expect(group.visibility_level).to eq(1)
        expect(group.mentionable_level).to eq(1)
        expect(group.messageable_level).to eq(1)
        expect(group.default_notification_level).to eq(1)
      end

      it 'triggers a extensibility event' do
        event = DiscourseEvent.track_events {
          put "/g/#{group.id}.json", params: { group: { flair_color: 'BBB' } }
        }.last

        expect(event[:event_name]).to eq(:group_updated)
        expect(event[:params].first).to eq(group)
      end
    end

    context "when user is not a group owner or admin" do
      it 'should not be able to update the group' do
        sign_in(user)

        put "/g/#{icij_group.id}.json", params: { group: { name: 'testing' } }

        expect(response.status).to eq(403)
      end
    end
  end

  describe "#categories" do
    let(:another_icij_group) do
      Fabricate(:icij_group, name: '0000', visibility_level: Group.visibility_levels[:members])
    end

    let(:another_private_cat) do
      cat = Fabricate(:category)
      cat.set_permissions(another_icij_group.id => 1)
      cat.save
      cat
    end

    let(:another_topic) do
      Fabricate(:topic, category: another_private_cat)
    end

    context "user is a member" do
      it "returns the right response if user is a member" do
        sign_in(user)

        get "/g/#{icij_group.name}/categories.json"

        expect(response.status).to eq(200)
      end

      it "returns the correct categories for that group" do
        sign_in(user)

        private_cat = Fabricate(:category)
        private_cat.set_permissions(icij_group.id => 1)
        private_cat.save

        icij_group.update!(categories: [private_cat])

        topic = Fabricate(:topic, category: private_cat)

        get "/g/#{icij_group.name}/categories.json"

        expect(response.status).to eq(200)
        json = JSON.parse(response.body)
        expect(json["lists"]["category_list"]["categories"].map { |c| c["id"] }).to eq([private_cat.id])
      end

      it "returns the correct topics for the categories in that group" do
        sign_in(user)

        private_cat = Fabricate(:category)
        private_cat.set_permissions(icij_group.id => 1)
        private_cat.save

        icij_group.update!(categories: [private_cat])

        topic = Fabricate(:topic, category: private_cat)

        get "/g/#{icij_group.name}/categories.json"

        expect(response.status).to eq(200)
        json = JSON.parse(response.body)
        expect(json["lists"]["topic_list"]["topics"].map { |t| t["id"] }).to eq([topic.id])
      end
    end

    context "user is not a member" do
      it "returns the right response if user is not a member" do
        sign_in(user)

        get "/g/#{another_icij_group.name}/categories.json"

        expect(response.status).to eq(403)
      end

      it "does not return the categories for that group" do
        sign_in(user)

        private_cat = Fabricate(:category)
        private_cat.set_permissions(icij_group.id => 1)
        private_cat.save

        icij_group.update!(categories: [private_cat])

        topic = Fabricate(:topic, category: private_cat)

        get "/g/#{icij_group.name}/categories.json"

        expect(response.status).to eq(200)
        json = JSON.parse(response.body)
        expect(json["lists"]["category_list"]["categories"].map { |c| c["id"] }).to_not eq([another_private_cat.id])
      end

      it "does not return the topics for the categories in that group" do
        sign_in(user)

        private_cat = Fabricate(:category)
        private_cat.set_permissions(icij_group.id => 1)
        private_cat.save

        icij_group.update!(categories: [private_cat])

        topic = Fabricate(:topic, category: private_cat)

        get "/g/#{icij_group.name}/categories.json"

        expect(response.status).to eq(200)
        json = JSON.parse(response.body)
        expect(json["lists"]["topic_list"]["topics"].map { |t| t["id"] }).to_not eq([another_topic.id])
      end
    end

    context "user is admin" do
      it "returns the right response if user is an admin" do
        sign_in(user)

        user.update!(admin: true)

        get "/g/#{another_icij_group.name}/categories.json"

        expect(response.status).to eq(200)
      end

      it "returns the categories for that group" do
        sign_in(user)

        user.update!(admin: true)

        private_cat = Fabricate(:category)
        private_cat.set_permissions(icij_group.id => 1)
        private_cat.save

        icij_group.update!(categories: [private_cat])

        topic = Fabricate(:topic, category: private_cat)

        another_icij_group.update!(categories: [another_private_cat])

        get "/g/#{another_icij_group.name}/categories.json"

        expect(response.status).to eq(200)
        json = JSON.parse(response.body)
        expect(json["lists"]["category_list"]["categories"].map { |c| c["id"] }).to eq([another_private_cat.id])
      end
    end
  end
end
