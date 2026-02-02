module.exports = function(eleventyConfig) {
    // Copy static assets
    // Map src/assets/images to /images in the output
    eleventyConfig.addPassthroughCopy("src/assets/images");
    
    // Copy CSS and JS from src/_includes if needed, 
    // but better to put them in assets if they are standalone
    // For now, let's just make sure assets are copied
    eleventyConfig.addPassthroughCopy("src/assets/css");
    eleventyConfig.addPassthroughCopy("src/assets/js");
    
    // Watch targets for development
    eleventyConfig.addWatchTarget("src/_data/");
    eleventyConfig.addWatchTarget("src/_includes/");
    
    // Add nl2br filter for WhatsApp examples
    eleventyConfig.addFilter("nl2br", function(str) {
        if (!str) return str;
        return str.replace(/\n/g, "<br>");
    });

    return {
        dir: {
            input: "src",
            output: "_site",
            includes: "_includes",
            layouts: "_layouts",
            data: "_data"
        },
        pathPrefix: "/",  // Ensure relative paths work
        htmlTemplateEngine: "njk",
        markdownTemplateEngine: "njk"
    };
};
