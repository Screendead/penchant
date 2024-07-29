const admin = require('firebase-admin');
const { Timestamp } = require('firebase-admin/firestore');
const serviceAccount = require('./privateKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

const vices = [
    { name: 'Marijuana', unit: 'puff' },
    { name: 'Booze', unit: 'drink' },
    { name: 'Cigarettes', unit: 'item' },
    { name: 'Junk Food', unit: 'item' },
    { name: 'Video Games', unit: 'minute' }
];

const ownerID = '1J6xVvHsFWYLPd5VPmI2t4nuGNo1';

async function populateVices() {
    const vicesRef = db.collection('vices');
    const viceActivitiesRef = db.collection('activities');

    const viceDocs = await Promise.all(vices.map(async (vice) => {
        const docRef = await vicesRef.add({
            name: vice.name,
            unit: vice.unit,
            ownerID: ownerID,
            createdAt: Timestamp.now()
        });
        return { id: docRef.id, ...vice };
    }));

    const now = Timestamp.now().toDate();
    const past30Days = Array.from({ length: 30 }, (_, i) => {
        const date = new Date(now);
        date.setDate(date.getDate() - i);
        return date;
    });

    for (const vice of viceDocs) {
        for (const date of past30Days) {
            const activitiesCount = Math.random() < 0.5
                ? Math.floor(Math.random() * 5) + 1
                : 0; // Random number of activities per day
            for (let i = 0; i < activitiesCount; i++) {
                const quantity = Math.floor(Math.random() * 5) + 1; // Random quantity between 1 and 5
                await viceActivitiesRef.add({
                    viceID: vice.id,
                    quantity: quantity,
                    ownerID: ownerID,
                    createdAt: Timestamp.fromDate(new Date(date.getTime() + Math.random() * 86400000)), // Random time within the day
                });
            }
        }
    }

    console.log('Data population complete.');
}

populateVices().catch(console.error);
