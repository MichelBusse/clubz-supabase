# Clubz - Supabase Project

Clubz - A Cross Platform Social Network App for Events - Supabase Backend

## Notes

This repository intends to be a reference for the backend of the [Clubz App](https://github.com/MichelBusse/clubz). The backend is created with [Supabase](https://supabase.com/), so the repository contains all implementation details for the database and edge functions. 

To view more information like screenshots and frontend code and to discover the live version of the app, go to the [main repo page](https://github.com/MichelBusse/clubz).

## Getting started

You can inspect the full database schema in the `supabase/migrations` directory. All edge functions used for the project are located in the `supabase/functions` directory. 

You can try to setup the project with the [Supabase CLI](https://supabase.com/docs/guides/cli/getting-started) and `supabase start`, but unfortunately the current CLI version seems to have some permission issues with the database postgis extension.

## Features

### Profiles
- Users can create a profile and follow other users.
- Profiles can be public or private, depending on who should see the profile activity
- Private profiles first have to accept follow requests, while public profiles accept them automatically and are visible to every user by default
- Users can upload a custom profile picture, choose a unique username and set a display name
- Profile pages display all profile information, including a follower count, a count of created events, a score for app usage and the profiles upcoming and past events 
- Users can view the created and attended events of the profiles they follow (and public profiles)

### Events
- Users can create events and share them with their  followers or other social media
- Various information can be added to events, including  name, image, start and end time, location, description and highlighted key information like dress code, ticket prices and age policy
- Users can choose to list their created events in their profile, while listed events by public profiles are visible to all users of the app
- Users can express their interest by attending or saving events, which can then be viewed by their followers 

### Feed
- Users get a personalized view of relevant events in their feed, depending on their location, the current time and the profiles they follow
- The feed can be filtered by city and radius

## App Security
- Permissions and rules for individual users (like which profiles and events a user can view and query) are managed by custom row level security rules for Supabase and Postgres