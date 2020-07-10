# frozen_string_literal: true

require 'rails_helper'
require 'rotp'

describe UsersController do
  let(:user) { Fabricate(:user) }

  describe '#summary' do
    it "returns a 404 for summary, as the summary page contains gratuitous information" do
      user = Fabricate(:user)
      create_post(user: user)

      get "/u/#{user.username_lower}/summary.json"
      expect(response.status).to eq(404)
    end

    it "returns 404 for a hidden profile" do
      user = Fabricate(:user)
      user.user_option.update_column(:hide_profile_and_presence, true)

      get "/u/#{user.username_lower}/summary.json"
      expect(response.status).to eq(404)
    end
  end


  describe '#show' do
    context "anon" do
      let(:user) { Discourse.system_user }

      it "returns failure because anon users cannot see other users' profiles" do
        get "/u/#{user.username}.json"
        expect(response.status).to eq(404)
      end

      it "should redirect to login page for anonymous user when profiles are hidden" do
        SiteSetting.hide_user_profiles_from_public = true
        get "/u/#{user.username}.json"
        expect(response).to redirect_to '/login'
      end

      describe "user profile views" do
        fab!(:other_user) { Fabricate(:user) }

        it "should not track a user profile view for an anon user, because anon users can't see other user's profiles if they're not in the same ICIJ projects" do
          get "/"
          UserProfileView.expects(:add).with(other_user.user_profile.id, request.remote_ip, nil).never
          get "/u/#{other_user.username}.json"
        end

        it "skips tracking" do
          UserProfileView.expects(:add).never
          get "/u/#{user.username}.json", params: { skip_track_visit: true }
        end
      end
    end

    # ICIJ SPEC
    context "logged-in user does not belong to the same ICIJ projects as the user in question" do
      let(:user) { Fabricate(:user) }
      let(:other_user_in_group) { Fabricate(:user) }

      let(:group) { Fabricate(:icij_group) }

      before do
        sign_in(user)

        group.users << other_user_in_group
        group.save
      end

      it 'returns not found when navigating to the profile of the other user' do
        get "/u/#{other_user_in_group.username}.json"
        expect(response.status).to eq(404)
        expect(response).not_to be_successful
      end

      it "returns not found when searching for a random username" do
        get "/u/madeuppity.json"
        expect(response).not_to be_successful
      end

      # FOR WHEN LOGGED-IN AND IN PROJECT
      # it 'returns not found when the user is inactive' do
      #   inactive = Fabricate(:user, active: false)
      #   get "/u/#{inactive.username}.json"
      #   expect(response).not_to be_successful
      # end

      # it 'returns success when show_inactive_accounts is true and user is logged in' do
      #   SiteSetting.show_inactive_accounts = true
      #   inactive = Fabricate(:user, active: false)
      #   get "/u/#{inactive.username}.json"
      #   expect(response.status).to eq(200)
      # end

      ## CAN'T FIGURE OUT WHY THIS ISN'T WORKING -- IT'S RETURNING A 500 ERROR BUT ONLY AFTER THE GUARDIAN INSTANCE IS CALLED
      # it "raises an error on invalid access" do
      #   byebug
      #   Guardian.any_instance.expects(:can_see?).with(user).returns(false)
      #   byebug
      #   get "/u/#{other_user_in_group.username}.json"
      #   expect(response).to be_forbidden
      # end

      describe "user profile views" do
        let(:another_user) { Fabricate(:user) }

        it "should not track a user profile view for a signed in user because that user is not part of the ICIJ project" do
          UserProfileView.expects(:add).never
          get "/u/#{another_user.username}.json"
        end

        # NOT WORKING
        it "should not track a user profile view for a user viewing his own profile" do
          UserProfileView.expects(:add).never
          get "/u/#{user.username}.json"
        end

        it "skips tracking" do
          UserProfileView.expects(:add).never
          get "/u/#{user.username}.json", params: { skip_track_visit: true }
        end
      end

      describe "include_post_count_for" do

        fab!(:admin) { Fabricate(:admin) }
        fab!(:topic) { Fabricate(:topic) }

        before do
          Fabricate(:post, user: user, topic: topic)
          Fabricate(:post, user: admin, topic: topic)
          Fabricate(:post, user: admin, topic: topic, post_type: Post.types[:whisper])
        end

        it "includes no posts because the logged-in user cannot see this profile" do
          get "/u/#{admin.username}.json", params: { include_post_count_for: topic.id }
          expect(response.status).to eq(404)
          expect(response).not_to be_successful
        end

        it "includes all post types for staff members" do
          sign_in(admin)

          get "/u/#{admin.username}.json", params: { include_post_count_for: topic.id }
          topic_post_count = JSON.parse(response.body).dig("user", "topic_post_count")
          expect(topic_post_count[topic.id.to_s]).to eq(2)
        end
      end
    end

    # ICIJ SPEC
    context "logged-in user does belong to the same ICIJ projects as the user in question" do
      let(:user) { Fabricate(:user) }
      let(:other_user_in_group) { Fabricate(:user) }

      let(:group) { Fabricate(:icij_group) }

      before do
        sign_in(user)

        group.users << user
        group.users << other_user_in_group
        group.save
      end

      it "returns a profile" do
        get "/u/#{other_user_in_group.username}.json"
        expect(response.status).to eq(200)
        parsed = JSON.parse(response.body)["user"]

        expect(parsed["username"]).to eq(other_user_in_group.username)
      end

      it "fails, if the other user is marked as hidden" do
        other_user_in_group.user_option.update_column(:hide_profile_and_presence, true)

        get "/u/#{other_user_in_group.username}.json"
        expect(response.status).to eq(404)
      end


      it "should be able to view a user if that user's profile name contains a period" do
        other_user_in_group.update!(username: 'test.test')
        get "/u/#{other_user_in_group.username}"

        expect(response.status).to eq(200)
        expect(response.body).to include(other_user_in_group.username)
      end
    end
  end

  describe "#show_card" do
    context "anon" do
      let(:user) { Discourse.system_user }

      it "returns success" do
        get "/u/#{user.username}/card.json"
        expect(response.status).to eq(404)
      end

      it "should redirect to login page for anonymous user when profiles are hidden" do
        SiteSetting.hide_user_profiles_from_public = true
        get "/u/#{user.username}/card.json"
        expect(response).to redirect_to '/login'
      end
    end

    context "logged in" do
      before do
        sign_in(user)
      end

      fab!(:user) { Fabricate(:user) }

      it 'works correctly' do
        get "/u/#{user.username}/card.json"
        expect(response.status).to eq(200)

        json = JSON.parse(response.body)

        expect(json["user"]["associated_accounts"]).to eq(nil) # Not serialized in card
        expect(json["user"]["username"]).to eq(user.username)
      end

      it "returns not found when the username doesn't exist" do
        get "/u/madeuppity/card.json"
        expect(response).not_to be_successful
      end

      it "raises an error on invalid access" do
        Guardian.any_instance.expects(:can_see?).with(user).returns(false)
        get "/u/#{user.username}/card.json"
        expect(response).to be_forbidden
      end
    end
  end

  describe '#badges' do
    it "should disable badges by default" do
      get "/u/#{user.username}/badges"
      expect(response.status).to eq(404)
    end

    it "fails if badges are disabled" do
      SiteSetting.enable_badges = false
      get "/u/#{user.username}/badges"
      expect(response.status).to eq(404)
    end
  end
end
