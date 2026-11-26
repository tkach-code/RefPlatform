import "dotenv/config";
import { config } from "dotenv";
import { MongoClient } from "mongodb";
import bcrypt from "bcryptjs";
import { pathToFileURL } from "node:url";

config({ path: ".env.local" });

const uri = process.env.MONGODB_URI;

export async function seedDatabase() {
  if (!uri) {
    throw new Error("MONGODB_URI is required");
  }

  const client = new MongoClient(uri);
  await client.connect();
  const db = client.db();

  console.log("Seeding database...");

  await Promise.all([
    db.collection("products").deleteMany({}),
    db.collection("categories").deleteMany({}),
    db.collection("mediaItems").deleteMany({}),
    db.collection("storySections").deleteMany({}),
    db.collection("events").deleteMany({}),
    db.collection("pageContent").deleteMany({}),
    db.collection("registrations").deleteMany({}),
    db.collection("users").deleteMany({}),
  ]);

  await db.collection("products").insertMany([
    {
      type: "home",
      title: "LEARN WITH PURPOSE",
      tagline: "SKILLS FOR TOMORROW",
      image: "/images/product-learn-purpose.svg",
      link: "/products",
      sortOrder: 1,
    },
    {
      type: "home",
      title: "PROGRAMMING COURSES",
      tagline: "BUILD REAL-WORLD EXPERTISE",
      image: "/images/product-programming-courses.svg",
      link: "/products",
      sortOrder: 2,
    },
    {
      type: "home",
      title: "EDUCATION PATHS",
      tagline: "LEARN, PRACTICE, GROW",
      image: "/images/product-education-paths.svg",
      link: "/products",
      sortOrder: 3,
    },
    {
      type: "products",
      title: "Frontend Development Bootcamp",
      tagline: "HTML, CSS, JavaScript, and React",
      description:
        "Build modern, responsive web experiences with hands-on projects, UI patterns, and real-world frontend workflows.",
      image: "/images/product-frontend-bootcamp.svg",
      link: "/products",
      sortOrder: 1,
    },
    {
      type: "products",
      title: "Python for Data and Automation",
      tagline: "Practical coding for analysis and efficiency",
      description:
        "Learn Python fundamentals, scripting, automation, and data workflows that help you solve real business problems faster.",
      image: "/images/product-python-data.svg",
      link: "/products",
      sortOrder: 2,
    },
    {
      type: "products",
      title: "Full-Stack Web Engineering",
      tagline: "From UX to APIs and deployment",
      description:
        "Master the complete product lifecycle with backend development, databases, editing workflows, and cloud-ready deployment skills.",
      image: "/images/product-fullstack-engineering.svg",
      link: "/products",
      sortOrder: 3,
    },
  ]);

  await db.collection("categories").insertMany([
    {
      title: "FRONTEND DEVELOPMENT",
      image: "/images/category-frontend.svg",
      sortOrder: 1,
    },
    {
      title: "PYTHON & DATA",
      image: "/images/category-python.svg",
      sortOrder: 2,
    },
    {
      title: "FULL-STACK ENGINEERING",
      image: "/images/category-fullstack.svg",
      sortOrder: 3,
    },
    {
      title: "DEV-OPS PRACTICES",
      image: "/images/category-devops.svg",
      sortOrder: 4,
    },
  ]);

  await db.collection("mediaItems").insertMany([
    {
      title: "Learning by Building",
      body: "Great software skills are built by solving real problems, not just reading tutorials. Our programs combine structured lessons with hands-on projects so learners can practice HTML, CSS, JavaScript, Python, APIs, and deployment workflows in a way that feels close to a real product team.",
      image: "/images/media-learning-building.svg",
      layout: "image-right",
      sortOrder: 1,
    },
    {
      title: "From Beginner to Builder",
      body: "Each learning path is designed to help students grow from foundational concepts into practical delivery. We focus on writing clean code, understanding architecture, debugging confidently, and building the habits that make technology work in the real world.",
      image: "/images/media-beginner-builder.svg",
      layout: "image-left",
      sortOrder: 2,
    },
    {
      title: "Practice That Sticks",
      body: "The best way to retain programming knowledge is to apply it repeatedly. Our curriculum emphasizes iterative learning, project feedback, and thoughtful revision so every lesson turns into usable experience and stronger confidence.",
      image: "/images/media-practice-sticks.svg",
      layout: "image-right",
      sortOrder: 3,
    },
  ]);

  await db.collection("storySections").insertMany([
    {
      title: "A New Way to Learn Tech",
      paragraphs: [
        "Education should prepare people to do real work, not just memorize abstract theory. That is why our programs are designed around practical exercises, guided implementation, and meaningful feedback. Learners move through project-based modules that teach how to reason clearly, build software, and communicate effectively in modern engineering teams.",
        "From frontend interfaces to backend systems and data workflows, each step helps students connect the fundamentals to actual product development. The goal is not just to understand code, but to become more confident, capable, and ready to solve problems in the real world.",
      ],
      sidebarTitle: "LEARN. BUILD. ITERATE.",
      sidebarBody:
        "Modern education is most effective when it blends theory, practice, feedback, and momentum across each project.",
      sidebarImage: "/images/media-learning-building.svg",
      sortOrder: 1,
    },
    {
      title: "Training for the Next Generation of Builders",
      paragraphs: [
        "Technology careers are changing fast, and learners need skills that translate into action. We help students develop a strong foundation in programming, product thinking, and analytical problem solving so they can keep growing in a demanding digital environment.",
        "By combining structured coursework with hands-on challenges, students learn how to work with code, data, interfaces, and systems in ways that reflect how modern teams operate. The result is a practical learning experience built for curiosity, confidence, and long-term skill development.",
      ],
      sidebarTitle: "PROGRAMMING WITH PURPOSE",
      sidebarBody: "Build skills that matter in real projects, real teams, and real careers.",
      sidebarImage: "/images/media-beginner-builder.svg",
      sortOrder: 2,
    },
  ]);

  await db.collection("events").insertOne({
    title: "FUTURE",
    subtitle: "EVENT",
    description:
      "Tickets are selling fast get yours today and be there in the future",
    ctaLabel: "SIGN UP TODAY",
    active: true,
  });

  await db.collection("pageContent").insertMany([
    {
      slug: "home",
      title: "LEARN SMARTER",
      subtitle: "BUILD REAL SKILLS",
      description: "Career-focused education for developers, analysts, and future-ready teams.",
      heroImage: "/images/banner.png",
    },
    {
      slug: "our-story",
      title: "OUR MISSION",
      subtitle: "MAKE LEARNING PRACTICAL",
      description:
        "We help people grow through hands-on education that connects theory with real-world projects.",
      heroImage: "/images/banner.png",
    },
    {
      slug: "products",
      title: "PROGRAMMING COURSES",
      subtitle: "PRACTICE-DRIVEN LEARNING",
      description: "Explore focused education tracks that build confidence, skill, and momentum.",
      heroImage: "/images/banner.png",
      paragraphs: [
        "Our learning paths are designed for people who want to build practical, job-ready skills in product development, data work, and modern software engineering.",
        "Each course combines foundational concepts with guided projects so learners can apply what they study immediately in real scenarios.",
        "Whether you are learning frontend design, backend systems, or data automation, the emphasis stays on clarity, craftsmanship, and measurable progress.",
        "We focus on helping students move from curiosity to capability with supportive instruction, structured milestones, and projects that reflect the way teams actually work.",
      ],
    },
    {
      slug: "media",
      title: "LEARN BY DOING",
      subtitle: "PROJECTS THAT BUILD CONFIDENCE",
      description: "See how our learning experiences turn theory into practical outcomes.",
      heroImage: "/images/banner.png",
    },
  ]);

  const email = process.env.ADMIN_EMAIL || "admin@refplatform.local";
  const password = process.env.ADMIN_PASSWORD || "changeme";
  const passwordHash = await bcrypt.hash(password, 10);

  await db.collection("users").insertOne({
    email,
    passwordHash,
    name: "Admin",
  });

  console.log(`Seeded admin user: ${email}`);
  console.log("Seed complete.");
  await client.close();
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  seedDatabase().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
