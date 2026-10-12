# Activating logins for staff, teachers and parents

> **Update:** admins can now create logins from the app. Staff list and Parents
> list → key icon ("Give login access") → tick one or many → *Give login
> access*. This runs the `provisionLogins` Cloud Function (deploy
> `functions/` first; Email/Password sign-in must be enabled in Firebase
> Authentication). It creates the Authentication account, the `users/{uid}`
> profile and the staff/parent link, and emails each person a set-password
> link. People with no/invalid email, an email already used by another
> account, or an existing login are listed and left unchanged. The manual
> procedure below remains as a fallback.

**Read this first — what the app can and cannot do today**

The app has **no screen that creates a login account** for someone else (the
*Users* page is still a placeholder), and a client app cannot create another
person's Firebase Authentication account. So giving a staff member, teacher or
parent a login is a short **admin procedure** using the Firebase Console,
plus two in-app steps. Do not ask people to use **Register**: that screen
creates a *new school* and makes them its administrator.

Three things must exist for a working login:

| # | What | Where it lives | Who creates it |
|---|---|---|---|
| 1 | The **person record** (staff / parent) | In the app (Staff, Parents) — or bulk upload | Admin, in the app |
| 2 | The **login** (email + password) → gives a **UID** | Firebase Console → Authentication | Admin, in the console |
| 3 | The **profile** `users/{UID}` (role, school, branch, status) | Firebase Console → Firestore | Admin, in the console |
| 4 | The **link** between 1 and 2/3 | Staff: in the app. Parent: console (see below) | Admin |

Until the profile's `status` is `ACTIVE`, the person lands on "Your account
isn't active yet" and sees no school data. `INVITED` and `DISABLED` are
blocked everywhere.

---

## A. Staff and teachers

1. **Person record** — Staff → *Add staff* (or *Import (CSV)*). Teachers:
   tick *Is teacher* / use the Teachers import. Note the person's email.
2. **Create the login** — Firebase Console → *Authentication* → *Users* →
   *Add user*: email + a temporary password. **Copy the User UID.**
3. **Create the profile** — Firebase Console → *Firestore Database* →
   collection `users` → *Add document* with **Document ID = the UID** and:

   | Field | Type | Value |
   |---|---|---|
   | `schoolId` | string | the school's document ID (Firestore: `schools/{schoolId}`) |
   | `branchId` | string | the branch's document ID (`schools/{schoolId}/branches/{branchId}`) |
   | `name` | string | full name |
   | `email` | string | same email as step 2 |
   | `phone` | string / null | optional |
   | `photoUrl` | null | |
   | `role` | string | `TEACHER`, `FINANCE` or `BRANCH_ADMIN` |
   | `status` | string | `ACTIVE` |
   | `linkedParentId` | null | |
   | `createdAt`, `updatedAt` | timestamp | now |
   | `createdBy`, `updatedBy` | string | `console` |

4. **Link in the app** — Staff → open the person → *Application account* →
   paste the **UID** → look it up → confirm the name/email/role → *Link
   account*. (This is what lets the app recognise "this login is that staff
   member": *My profile*, own attendance, own leave, own timetable.)
5. **Teaching access** — for a teacher, add their class/subject assignments
   on the staff profile's *Teaching* tab; leave types apply by role and
   employment type.
6. **Hand over** — give them the email and temporary password. At first
   sign-in they can use *Forgot password* to set their own.

## B. Parents

1. **Person record and children** — Parents → add the parent (or include the
   parent columns in the student bulk upload), then link the parent to each
   child (Student → *Parents* → link). **Tick "Allow parent portal access"
   on that link** — without it the parent signs in but sees none of that
   child's data. (A student bulk upload leaves it **off**; enable it per link.)
2. **Create the login** — Firebase Console → *Authentication* → *Add user*
   (the parent's email + temporary password). Copy the **UID**.
3. **Create the profile** — Firestore → `users` → document ID = **UID**:
   same fields as section A, but `role` = `PARENT`, `branchId` = the
   children's branch, `status` = `ACTIVE`, and **`linkedParentId` = the
   parent record's document ID** (Firestore: `schools/{s}/branches/{b}/parents/{parentId}`).
4. **Link the other direction** — in that same `parents/{parentId}`
   document set `linkedUserId` (string) = the **UID**. *(There is no screen
   for this yet; the parent page says "Portal access is granted from Users
   management", which is not built.)*
5. **Verify** — sign in as the parent: the navigation shows *My fees*, *My
   leave*, *My homework*, *My results*, *My timetable* for the linked child
   only.

## C. Common problems

| Symptom | Cause |
|---|---|
| "Your account isn't active yet" | `users/{UID}.status` is `INVITED` — set to `ACTIVE` |
| "Your account has been disabled" | status `DISABLED` |
| Lands on "Create your school" | there is **no** `users/{UID}` document (step 3 missing, or the document ID is not the UID) |
| Parent sees no children / empty fees | `linkedParentId` missing/wrong, or the parent–student link has portal access off |
| Teacher can't see classes | no teacher assignments yet, or role isn't `TEACHER` |
| Wrong school's data / nothing | `schoolId` / `branchId` copied incorrectly |

## D. Disabling someone

Set `users/{UID}.status` to `DISABLED` (no deletes). To remove the staff
link, use *Unlink account* on the staff profile.

---

### Recommended follow-up

A real **Users management** screen would remove steps 2–4 for everyone but
the Authentication user: an admin creates the profile (the Firestore rules
already allow a school/branch admin to create `users/{uid}` for TEACHER,
FINANCE, PARENT, BRANCH_ADMIN with status `ACTIVE`/`INVITED`) and links
parents in one place. Creating the Authentication account itself needs a
Cloud Function (or an invite-by-email flow), because a client cannot create
another user's login.
