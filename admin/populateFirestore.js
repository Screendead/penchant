// Seeds the Firebase emulators under a demo- project. It refuses to run
// against anything else, and needs no credentials.
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

const projectId = process.env.SEED_PROJECT_ID || 'demo-tracker';
const seedEmail = 'seed@example.com';
const seedPassword = 'seed-password';

function requireEmulators() {
    const missing = ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']
        .filter((name) => !process.env[name]);
    if (missing.length > 0) {
        throw new Error(`Refusing to run: ${missing.join(' and ')} not set. This script seeds emulators only.`);
    }
    if (!projectId.startsWith('demo-')) {
        throw new Error(`Refusing to run: project id "${projectId}" does not start with demo-.`);
    }
}

// Units are the names of the Unit enum in lib/data/unit.dart.
const vices = [
    { name: 'Marijuana', unit: 'puff', archived: false },
    { name: 'Booze', unit: 'drink', archived: false },
    { name: 'Cigarettes', unit: 'item', archived: false },
    { name: 'Junk Food', unit: 'item', archived: false },
    { name: 'Video Games', unit: 'hour', archived: false },
    { name: 'Old Habit', unit: 'time', archived: true },
];

async function seedUser(auth) {
    try {
        return await auth.getUserByEmail(seedEmail);
    } catch (e) {
        if (e.code !== 'auth/user-not-found') throw e;
        return auth.createUser({ email: seedEmail, password: seedPassword, displayName: 'Seed User' });
    }
}

async function deleteOwnedDocs(db, collection, ownerID) {
    const snapshot = await db.collection(collection).where('ownerID', '==', ownerID).get();
    const writer = db.bulkWriter();
    snapshot.docs.forEach((doc) => writer.delete(doc.ref));
    await writer.close();
}

async function populate() {
    requireEmulators();
    initializeApp({ projectId });
    const db = getFirestore();
    const ownerID = (await seedUser(getAuth())).uid;

    // Re-running replaces the seed user's data instead of duplicating it.
    await deleteOwnedDocs(db, 'activities', ownerID);
    await deleteOwnedDocs(db, 'vices', ownerID);

    const writer = db.bulkWriter();
    const viceIDs = vices.map((vice) => {
        const ref = db.collection('vices').doc();
        writer.create(ref, { ...vice, ownerID, createdAt: Timestamp.now() });
        return ref.id;
    });

    const now = new Date();
    let activityCount = 0;
    viceIDs.forEach((viceID, index) => {
        if (vices[index].archived) return;
        const sampleTriggers = [
            ['work/meeting'],
            ['feeling/stressed', 'work/deadline'],
            ['social/friends', 'place/bar'],
            ['routine/morning'],
            ['Late train'],
        ];
        for (let day = 0; day < 30; day++) {
            if (Math.random() >= 0.5) continue;
            const count = Math.floor(Math.random() * 5) + 1;
            for (let i = 0; i < count; i++) {
                const date = new Date(now);
                date.setDate(date.getDate() - day);
                // Optional: about half the entries carry none, as entries logged
                // before triggers existed do.
                const triggers = sampleTriggers[Math.floor(Math.random() * sampleTriggers.length * 2)];
                writer.create(db.collection('activities').doc(), {
                    viceID,
                    quantity: Math.floor(Math.random() * 5) + 1,
                    ownerID,
                    createdAt: Timestamp.fromDate(new Date(date.getTime() - Math.random() * 86400000)),
                    ...(triggers ? { triggers } : {}),
                });
                activityCount++;
            }
        }
    });
    await writer.close();

    console.log(`Seeded ${vices.length} vices and ${activityCount} activities for ${seedEmail} (${ownerID}) in ${projectId}.`);
}

populate().catch((e) => {
    console.error(e.message);
    process.exit(1);
});
